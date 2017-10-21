pragma solidity ^0.4.17;

/**
 * @title Payroll
 */

import "./EmployeeLibrary.sol";
import "./PayrollLibrary.sol";
import "./SharedLibrary.sol";

import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";


contract Payroll is Pausable {

    using EmployeeLibrary for address;
    using PayrollLibrary for PayrollLibrary.Payroll;

    PayrollLibrary.Payroll public payroll;

    modifier onlyEmployee() {
        require(payroll.db.isEmployee());
        _;
    }

    event OnEmployeeAdded(
        uint256 indexed employeeId,
        address account,
        uint256 indexed yearlyUSDSalary
    );
    event OnEmployeeSalaryUpdated(
        uint256 indexed employeeId,
        uint256 indexed yearlyUSDSalary
    );
    event OnEmployeeRemoved(uint256 indexed employeeId);
    event OnEthFundsAdded(address account, uint256 indexed ethfunds);
    event OnAllocationChanged(
        uint256 indexed employeeId,
        address token,
        uint256 alloc
    );
    event OnPaid(uint256 indexed employeeId, uint256 indexed monthlyUSDSalary);

    function Payroll(
        address _db,
        address antToken,
        address usdToken,
        address escapeHatch
    )
        public
    {
        // constructor
        payroll.setDBAddress(_db);
        payroll.setTokenAddresses(antToken, usdToken);
        payroll.setEscapeHatch(escapeHatch);
    }

    function getEmployeeCount()
        external view returns (uint256)
    {
        return payroll.db.getEmployeeCount();
    }

    function getEmployeeId(address account)
        external view returns (uint256)
    {
        return payroll.db.getEmployeeId(account);
    }

    function getEmployee(uint256 employeeId)
        external view returns (bool, address, uint256)
    {
        var (active,employee,,yearlyUSDSalary) = payroll.db.getEmployee(
            employeeId
        );
        return (active, employee, yearlyUSDSalary);
    }

    function calculatePayrollBurnrate()
        external view returns (uint256)
    {
        return payroll.calculatePayrollBurnrate();
    }

    function calculatePayrollRunway()
        external view returns (uint256)
    {
        return payroll.calculatePayrollRunway();
    }

    function calculatePayrollRunwayInMonths()
        external view returns (uint256)
    {
        return payroll.calculatePayrollRunwayInMonths();
    }

    function setDBAddress(address _db)
        onlyOwner
        external
    {
        payroll.setDBAddress(_db);
    }

    function setTokenAddresses(address ant, address usd)
        onlyOwner
        external
    {
        payroll.setTokenAddresses(ant, usd);
    }

    function addEmployee(
        address   accountAddress,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    )
        onlyOwner
        external
    {
        payroll.db.addEmployee(
            accountAddress,
            allowedTokens,
            initialYearlyUSDSalary
        );
    }

    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary)
        onlyOwner
        external
    {
        payroll.db.setEmployeeSalary(employeeId, yearlyUSDSalary);
    }

    function removeEmployee(uint256 employeeId)
        onlyOwner
        external
    {
        payroll.db.removeEmployee(employeeId);
    }

    function addFunds()
        payable
        external
    {
        require(msg.value > 0);
        OnEthFundsAdded(msg.sender, msg.value);
    }

    function escapeHatch()
        onlyOwner
        external
    {
        EscapeHatch(payroll.escapeHatch).pauseFromPayroll();
    }

    function emergencyWithdraw()
        onlyOwner
        whenPaused
        external
    {
        address[] memory tokens = new address[](2);
        tokens[0] = payroll.antToken;
        tokens[1] = payroll.usdToken;
        SharedLibrary.withdrawFrom(this, tokens);
    }

    function determineAllocation(address[] tokens, uint256[] distribution)
        onlyEmployee
        whenNotPaused
        external
    {
        payroll.db.setEmployeeTokenAllocation(tokens, distribution);
    }

    function payday()
        onlyEmployee
        whenNotPaused
        external
    {
        payroll.payday();
    }

    function updateExchangeRates()
        external
    {
        payroll.updateExchangeRates();
    }

    function __callback(bytes32 id, string result)
        external
    {
        payroll.setExchangeRateByOraclize(id, result);
    }

    /// @notice oraclize use __callback to import data. I haven't found
    /// a way to change it to use a differnt name, so please treat _callback
    /// as setExchangeRate that is defined in PayrollInterface.
    function setExchangeRate(address token, uint256 usdExchangeRate)
        onlyOwner
        external
    {
        payroll.setExchangeRate(token, usdExchangeRate);
    }

}
