pragma solidity ^0.4.17;

/**
 * @title PayrollLibrary
 * @dev This library implement most of logic code for Payroll contract.
 */

import "./EscapeHatch.sol";
import "./EmployeeLibrary.sol";
import "./SharedLibrary.sol";

import "zeppelin-solidity/contracts/token/ERC20.sol";
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
        // special value reference to ETH => USD exchange rate
        address eth;
        address hatch;

        uint256 nextPayDay;
        uint256 payRound;

        // payRound => amount
        mapping (uint256 => uint256) unpaidUSDSalaries;
        // exchange rates
        // x USD to 1 ANT
        // x USD to 1 ETH (ETH use 0xeth special address)
        // 1 USD to 1 USD
        mapping (address => uint256) exchangeRates;
        // payRound => (account => isPaid)
        mapping (uint256 => mapping (address => bool)) payStats;
        mapping (bytes32 => uint256) isOracleId;
    }

    event OnPaid(uint256 indexed employeeId, uint256 indexed monthlyUSDSalary);

    /// @dev Check if msg.sender is active employee
    /// @param self Payroll Payroll data struct
    function isEmployee(Payroll storage self)
        internal view returns (bool)
    {
        return self.db.isEmployee();
    }

    /// @dev Get the number of active employee
    /// @param self Payroll Payroll data struct
    /// @return uint256 active employee count
    function getEmployeeCount(Payroll storage self)
        internal view returns (uint256)
    {
        return self.db.getEmployeeCount();
    }

    /// @dev Get the corresponding employee id
    /// @param self Payroll Payroll data struct
    /// @param account address employee account address
    /// @return uint256 employee id
    function getEmployeeId(Payroll storage self, address account)
        internal view returns (uint256)
    {
        return self.db.getEmployeeId(account);
    }

    /// @dev Get employee info for given id
    /// @param self Payroll Payroll data struct
    /// @param employeeId uint256 given employee id to query
    /// @return bool if employee is active
    /// @return address employee account
    /// @return uint256 yearly USD salary
    function getEmployee(Payroll storage self, uint256 employeeId)
        internal view returns (bool, address, uint256)
    {
        var (active,employee,,yearlyUSDSalary) = self.db.getEmployee(
            employeeId
        );
        return (active, employee, yearlyUSDSalary);
    }

    /// @dev Calculate Monthly USD amount spent in salaries
    /// @param self Payroll Payroll data struct
    /// @return uint256 monthly USD salaries
    function calculatePayrollBurnrate(Payroll storage self)
        internal view returns (uint256)
    {
        return self.db.getUSDMonthlySalaries();
    }

    /// @dev Calculate months until the contract run out of funds
    /// @notice We assume the pay day is same for all employees
    /// @param self Payroll Payroll data struct
    /// @return uint256 left months
    function calculatePayrollRunwayInMonths(Payroll storage self)
        internal view returns (uint256)
    {
        uint256 unpaidUSDSalaries = self.unpaidUSDSalaries[self.payRound];
        uint256 usdFunds = ERC20(self.usdToken).balanceOf(this);

        // ANT token (x USD to 1 ANT)
        uint256 antExchangeRate = self.exchangeRates[self.antToken];
        uint256 antFunds = ERC20(self.antToken).balanceOf(this);
        // antFunds * antExchangeRate
        usdFunds = usdFunds.add(antFunds.mul(antExchangeRate));

        // ETH (x USD to 1 ETH)
        uint256 ethExchangeRate = self.exchangeRates[self.eth];
        // ethFunds * ethExchangeRate
        usdFunds = usdFunds.add(this.balance.mul(ethExchangeRate));

        usdFunds = usdFunds.sub(unpaidUSDSalaries);
        uint256 usdMonthlySalaries = self.db.getUSDMonthlySalaries();
        // usdFunds / sudMonthlySalaries
        return usdFunds.div(usdMonthlySalaries);
    }

    /// @dev Calculate days until the contract run out of funds
    /// @notice We assume the pay day is same for all employees
    /// @param self Payroll Payroll data struct
    /// @return uint256 left days
    function calculatePayrollRunway(Payroll storage self)
        internal view returns (uint256)
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

    /// @dev Set PayrollDB address
    /// @param self Payroll Payroll data struct
    /// @param _db address Deployed PayrollDB address
    function setDBAddress(Payroll storage self, address _db)
        internal
    {
        require(_db != 0x0);

        self.db = _db;
    }

    /// @dev Set ANT token and USD token addresses
    /// @param self Payroll Payroll data struct
    /// @param _ant address Deployed ANT token address
    /// @param _usd address Deployed USD token address
    /// @param _eth address special value reference ETH => USD exchange rate
    function setTokenAddresses(
        Payroll storage self,
        address _ant,
        address _usd,
        address _eth
    )
        internal
    {
        require(_ant != 0x0 && _usd != 0x0);

        self.antToken = _ant;
        self.usdToken = _usd;
        self.eth = _eth;

        // set up default rate to 1 USD to 1 USD for usdToken
        setExchangeRate(self, _usd, 1);
    }

    /// @dev Set escape hatch address
    /// @param self Payroll Payroll data struct
    /// @param _escapeHatch address Deployed escape hatch contract address
    function setEscapeHatch(Payroll storage self, address _escapeHatch)
        internal
    {
        require(_escapeHatch != 0x0);

        self.hatch = _escapeHatch;
    }

    /// @dev Add new employee
    /// @param self Payroll Payroll data struct
    /// @param accountAddress address employee address
    /// @param allowedTokens address[] allowed tokens for salary payment
    /// @param initialYearlyUSDSalary uint256 salary in USD for year
    function addEmployee(
        Payroll storage self,
        address   accountAddress,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    )
        internal
    {
        self.db.addEmployee(
            accountAddress,
            allowedTokens,
            initialYearlyUSDSalary
        );
    }

    /// @dev Set employee yearly salary
    /// @param self Payroll Payroll data struct
    /// @param employeeId uint256 give id to query
    /// @param yearlyUSDSalary uint256 salary in USD for year
    function setEmployeeSalary(
        Payroll storage self,
        uint256 employeeId,
        uint256 yearlyUSDSalary
    )
        internal
    {
        self.db.setEmployeeSalary(employeeId, yearlyUSDSalary);
    }

    /// @dev Remove employee
    /// @param self Payroll Payroll data struct
    /// @param employeeId uint256 given id to remove
    function removeEmployee(Payroll storage self, uint256 employeeId)
        internal
    {
        self.db.removeEmployee(employeeId);
    }

    /// @dev Set employee allowed tokens allocation
    /// @param self Payroll Payroll data struct
    /// @param tokens address[] allowed tokens
    /// @param distribution uint256[] tokens allocation
    function determineAllocation(
        Payroll storage self,
        address[] tokens,
        uint256[] distribution
    )
        internal
    {
        self.db.setEmployeeTokenAllocation(tokens, distribution);
    }

    /// @dev Pause escape hatch contract
    /// @param self payroll Payroll data struct
    function escapeHatch(Payroll storage self)
        internal
    {
        EscapeHatch(self.hatch).pauseFromPayroll();
    }

    /// @dev Pay salary to employee
    /// @notice We assume all employees take their salaries every months. Also
    /// employee can only call this function once per month.
    /// @param self Payroll Payroll data struct
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
            self.unpaidUSDSalaries[payRound] = unpaidUSDSalaries.add(
                usdMonthlySalaries
            );

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

    /// @dev Withdraw all token and eth
    /// @param self Payroll Payroll data struct
    function emergencyWithdraw(Payroll storage self)
        internal
    {
        address[] memory tokens = new address[](2);
        tokens[0] = self.antToken;
        tokens[1] = self.usdToken;
        SharedLibrary.withdrawFrom(this, tokens);
    }

    /// @dev Use oraclize oracle to fetch latest token exchange rates
    /// @param self Payroll Payroll data struct
    function updateExchangeRates(Payroll storage self)
        internal
    {
        uint delay = 10;
        string memory ANT_TO_USD = "json(https://min-api.cryptocompare.com/data/price?fsym=ANT&tsyms=USD).USD";
        string memory ETH_TO_USD = "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD";

        bytes32 antId = oraclizeLib.oraclize_query(delay, "URL", ANT_TO_USD);
        bytes32 ethId = oraclizeLib.oraclize_query(delay, "URL", ETH_TO_USD);

        self.isOracleId[antId] = 1;
        self.isOracleId[ethId] = 2;
    }

    /// @dev Callback function used by oraclize to actually set token exchange
    /// rate.
    /// @param self Payroll Payroll data struct
    /// @param id bytes32 oraclize generated id per querying
    /// @param result string oraclize querying result, toke exchange rate
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
            setExchangeRate(self, self.eth, rate);
        }
    }

    /// @dev Set token exchange rate
    /// @param self Payroll Payroll data struct
    /// @param token address target token
    /// @param usdExchangeRate uint256 exchange rate
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

    /// @dev Pay to employee
    /// @param self Payroll Payroll data struct
    /// @param employeeId uint256 specified employee to pay
    function pay(Payroll storage self, uint256 employeeId)
        private
    {
        var (,account,monthlyUSDSalary,) = self.db.getEmployee(employeeId);
        var tokens = self.db.getEmployeeTokens(employeeId);
        var tokensAllocation = self.db.getEmployeeTokensAlloc(employeeId);
        uint256 payRound = self.payRound;

        self.unpaidUSDSalaries[payRound] = self.unpaidUSDSalaries[payRound].sub(
            monthlyUSDSalary
        );

        uint256 leftUSDSalary = payInToken(
            self,
            account,
            monthlyUSDSalary,
            tokens,
            tokensAllocation
        );

        // handle left ether
        uint ethAmount = 0;
        if (leftUSDSalary > 0) {
            // x USD to 1 ether
            uint ethExchangeRate = self.exchangeRates[self.eth];
            // leftUSDSalary / ethExchangeRate
            ethAmount = leftUSDSalary.div(ethExchangeRate);
            EscapeHatch(self.hatch).quarantine.value(ethAmount)(
                account,
                new address[](0),
                new uint256[](0)
            );
        }

        OnPaid(employeeId, monthlyUSDSalary);
    }

    /// @dev Pay to employee
    /// @param self Payroll Payroll data struct
    /// @param account address employee account address
    /// @param monthlyUSDSalary uint256 monthly usd salary
    /// @param tokens address[] allowed tokens
    /// @param allocation uint256[] tokens allocation
    /// @return uint256 left unpaid usd salary
    function payInToken(
        Payroll storage self,
        address account,
        uint256 monthlyUSDSalary,
        address[] tokens,
        uint256[] allocation
    )
        private returns (uint256)
    {
        uint256 leftUSDSalary = monthlyUSDSalary;
        uint256[] memory payAmounts = new uint256[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            if (leftUSDSalary == 0) {
                break;
            }
            if (allocation[i] == 0) {
                continue;
            }

            // monthlyUSDSalary * allocation / 100
            uint usdAmount = monthlyUSDSalary.mul(allocation[i]).div(100);
            leftUSDSalary = leftUSDSalary.sub(usdAmount);

            // XXX token (x USD to 1 XXX)
            uint exRate = self.exchangeRates[tokens[i]];
            // usdAmount / exRate
            uint tAmount = usdAmount.div(exRate);
            payAmounts[i] = tAmount;
            ERC20(tokens[i]).transfer(self.hatch, tAmount);
        }

        EscapeHatch(self.hatch).quarantine(account, tokens, payAmounts);
        return leftUSDSalary;
    }

}
