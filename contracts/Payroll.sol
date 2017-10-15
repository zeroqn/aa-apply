pragma solidity ^0.4.15;

/**
 * @title Payroll
 */

import "./EmployeeLibrary.sol";
import "./PayrollLibrary.sol";

import "./mocks/USDToken.sol";
import "./mocks/ANTToken.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";

contract Payroll is Ownable, Pausable {

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
    event OnPaid(uint256 indexed employeeId, uint256 indexed USDSalary);

    function Payroll(address _db, address antToken, address usdToken) {
        // constructor
        payroll.setDBAddress(_db);
        payroll.setTokenAddresses(antToken, usdToken);
    }

    function getEmployeeCount()
        external constant returns (uint256)
    {
        return payroll.db.getEmployeeCount();
    }

    function getEmployeeId(address account)
        external constant returns (uint256)
    {
        return payroll.db.getEmployeeId(account);
    }

    function getEmployee(uint256 employeeId)
        external constant returns (bool active,
                                   address employee,
                                   uint256 yearlyUSDSalary)
    {
        (active,employee,,yearlyUSDSalary) = payroll.db.getEmployee(employeeId);
        return (active, employee, yearlyUSDSalary);
    }

    function calculatePayrollBurnrate()
        external constant returns (uint256)
    {
        return payroll.calculatePayrollBurnrate();
    }

    function calculatePayrollRunway()
        external constant returns (uint256)
    {
        return payroll.calculatePayrollRunway();
    }

    function calculatePayrollRunwayInMonths()
        external constant returns (uint256)
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
        payroll.db.addEmployee(accountAddress,
                               allowedTokens,
                               initialYearlyUSDSalary);
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
        pause();
    }

    function emergencyWithdraw()
        onlyOwner
        whenPaused
        external
    {
        ANTToken antToken = ANTToken(payroll.antToken);
        USDToken usdToken = USDToken(payroll.usdToken);
        uint256 antAmount = antToken.balanceOf(this);
        uint256 usdAmount = usdToken.balanceOf(this);

        msg.sender.transfer(this.balance);
        antToken.transfer(msg.sender, antAmount);
        usdToken.transfer(msg.sender, usdAmount);
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
