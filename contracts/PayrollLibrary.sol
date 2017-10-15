pragma solidity ^0.4.15;

/**
 * @title PayrollLibrary
 * @dev This library implement most of logic code for Payroll contract.
 */

import "./EmployeeLibrary.sol";

import "./mocks/USDToken.sol";
import "./mocks/ANTToken.sol";
import "./oraclizeAPI.lib.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";

library PayrollLibrary {

    using SafeMath for uint256;
    using EmployeeLibrary for address;

    struct Payroll {
        // PayrollDB
        address db;
        // USD token
        address usdToken;
        // ANT token
        address antToken;

        uint256 nextPayDay;
        uint256 payRound;

        // payRound => amount
        mapping (uint256 => uint256) unpaidUSDSalaries;
        // exchange rates
        // x USD to 1 ANT
        // x USD to 1 ether
        mapping (address => uint256) exchangeRates;
        // payRound => (account => isPaid)
        mapping (uint256 => mapping (address => bool)) payStats;
        mapping (bytes32 => uint256) isOracleId;
    }

    event OnPaid(uint256 indexed employeeId, uint256 indexed USDSalary);

    function calculatePayrollBurnrate(Payroll storage self)
        internal constant returns (uint256)
    {
        return self.db.getUSDMonthlySalaries();
    }

    function calculatePayrollRunwayInMonths(Payroll storage self)
        internal constant returns (uint256)
    {
        uint256 unpaidUSDSalaries = self.unpaidUSDSalaries[self.payRound];
        uint256 usdFunds = USDToken(self.usdToken).balanceOf(this);

        // ANT token (x USD to 1 ANT)
        uint256 antExchangeRate = self.exchangeRates[self.antToken];
        uint256 antFunds = ANTToken(self.antToken).balanceOf(this);
        // antFunds * antExchangeRate
        usdFunds = usdFunds.add(antFunds.mul(antExchangeRate));

        // ether (x USD to 1 ether)
        uint256 usdExchangeRate = self.exchangeRates[self.usdToken];
        // etherFunds * usdExchangeRate
        usdFunds = usdFunds.add(this.balance.mul(usdExchangeRate));

        usdFunds = usdFunds.sub(unpaidUSDSalaries);
        uint256 usdMonthlySalaries = self.db.getUSDMonthlySalaries();
        // usdFunds / sudMonthlySalaries
        return usdFunds.div(usdMonthlySalaries);
    }

    /// @notice We assume the pay day is same for all employees
    function calculatePayrollRunway(Payroll storage self)
        internal constant returns (uint256)
    {
        uint256 ONE_MONTH = 4 weeks;
        uint256 date = self.nextPayDay;
        uint256 leftMonths = calculatePayrollRunwayInMonths(self);

        if (date == 0) {
            // nothing paid yet
            date = now;
        } else {
            // calculate from previous payday
            date = date.sub(ONE_MONTH);
        }
        return date.add(leftMonths.mul(ONE_MONTH));
    }

    function setDBAddress(Payroll storage self, address _db)
        internal
    {
        require(_db != 0x0);

        self.db = _db;
    }

    function setTokenAddresses(Payroll storage self, address ant, address usd)
        internal
    {
        require(ant != 0x0 && usd != 0x0);

        self.antToken = ant;
        self.usdToken = usd;
    }

    /// @notice We assume all employees take their salaries every month
    function payday(Payroll storage self)
        internal
    {
        uint ONE_MONTH = 4 weeks;
        uint payRound = self.payRound;
        uint nextPayDay = self.nextPayDay;
        uint unpaidUSDSalaries = self.unpaidUSDSalaries[payRound];

        if (now > nextPayDay) {
            // start next pay round
            uint256 usdMonthlySalaries = self.db.getUSDMonthlySalaries();
            payRound = payRound.add(1);
            self.unpaidUSDSalaries[payRound] =
                unpaidUSDSalaries.add(usdMonthlySalaries);

            self.payRound = payRound;
            if (nextPayDay == 0) {
                // this is first payment
                nextPayDay = now;
            }
            self.nextPayDay = nextPayDay.add(ONE_MONTH);
        }

        if (self.payStats[payRound][msg.sender]) {
            revert();
        }
        self.payStats[payRound][msg.sender] = true;

        pay(self, self.db.getEmployeeId(msg.sender));
    }

    function updateExchangeRates(Payroll storage self)
        internal
    {
        uint delay = 10;
        var ANT_TO_USD = "json(https://min-api.cryptocompare.com/data/price?fsym=ANT&tsyms=USD).USD";
        var ETH_TO_USD = "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD";

        bytes32 antId = oraclizeLib.oraclize_query(delay, "URL", ANT_TO_USD);
        bytes32 ethId = oraclizeLib.oraclize_query(delay, "URL", ETH_TO_USD);

        self.isOracleId[antId] = 1;
        self.isOracleId[ethId] = 2;
    }

    function setExchangeRateByOraclize(
        Payroll storage self,
        bytes32 id,
        string result
    )
        internal
    {
        require(self.isOracleId[id] > 0 && self.isOracleId[id] < 3);
        require(msg.sender == oraclizeLib.oraclize_cbAddress());

        uint256 rate = oraclizeLib.parseInt(result, 2);
        if (self.isOracleId[id] == 1) {
            setExchangeRate(self, self.antToken, rate);
        } else if (self.isOracleId[id] == 2) {
            setExchangeRate(self, self.usdToken, rate);
        }
    }

    function setExchangeRate(
        Payroll storage self,
        address token,
        uint256 usdExchangeRate
    )
        internal
    {
        require(usdExchangeRate > 0);

        self.exchangeRates[token] = usdExchangeRate;
    }

    function pay(Payroll storage self, uint256 employeeId)
        private
    {
        var (,account,monthlyUSDSalary,) = self.db.getEmployee(employeeId);
        var tokens = self.db.getEmployeeTokens(employeeId);
        var tokensAllocation = self.db.getEmployeeTokensAlloc(employeeId);
        uint256 payRound = self.payRound;
        uint256 leftUSDSalary = monthlyUSDSalary;

        self.unpaidUSDSalaries[payRound] =
            self.unpaidUSDSalaries[payRound].sub(monthlyUSDSalary);

        for (uint i = 0; i < tokens.length; i++) {
            if (leftUSDSalary == 0) {
                break;
            }
            if (tokensAllocation[i] == 0) {
                continue;
            }

            // monthlyUSDSalary * allocation / 100
            uint usdAmount = monthlyUSDSalary.mul(tokensAllocation[i]).div(100);
            leftUSDSalary = leftUSDSalary.sub(usdAmount);

            if (tokens[i] == self.usdToken) {
                USDToken(self.usdToken).transfer(account, usdAmount);
            } else {
                // ANT token (x USD to 1 ANT)
                uint antExchangeRate = self.exchangeRates[tokens[i]];
                // usdAmount / antExchangeRate
                uint antAmount = usdAmount.div(antExchangeRate);
                ANTToken(self.antToken).transfer(account, antAmount);
            }
        }

        // handle left ether
        if (leftUSDSalary > 0) {
            // x USD to 1 ether
            uint ethExchangeRate = self.exchangeRates[self.usdToken];
            // leftUSDSalary / ethExchangeRate
            uint etherAmount = leftUSDSalary.div(ethExchangeRate);
            account.transfer(etherAmount);
        }

        OnPaid(employeeId, monthlyUSDSalary);
    }

}
