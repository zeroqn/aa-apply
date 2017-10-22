pragma solidity ^0.4.17;

/**
 * @title Payroll
 */

import "./PayrollLibrary.sol";

import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";


contract Payroll is Pausable {

    using PayrollLibrary for PayrollLibrary.Payroll;

    PayrollLibrary.Payroll public payroll;
    // special value is used to reference ETH => USD exchange rate
    address public ethAddr = 0xeeee;

    modifier onlyEmployee() {
        require(payroll.isEmployee());
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
        payroll.setTokenAddresses(antToken, usdToken, ethAddr);
        payroll.setEscapeHatch(escapeHatch);
    }

    function getEmployeeCount()
        external view returns (uint256)
    {
        return payroll.getEmployeeCount();
    }

    function getEmployeeId(address account)
        external view returns (uint256)
    {
        return payroll.getEmployeeId(account);
    }

    function getEmployee(uint256 employeeId)
        external view returns (bool, address, uint256)
    {
        return payroll.getEmployee(employeeId);
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
        payroll.setTokenAddresses(ant, usd, ethAddr);
    }

    function addEmployee(
        address   accountAddress,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    )
        onlyOwner
        external
    {
        payroll.addEmployee(
            accountAddress,
            allowedTokens,
            initialYearlyUSDSalary
        );
    }

    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary)
        onlyOwner
        external
    {
        payroll.setEmployeeSalary(employeeId, yearlyUSDSalary);
    }

    function removeEmployee(uint256 employeeId)
        onlyOwner
        external
    {
        payroll.removeEmployee(employeeId);
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
        payroll.escapeHatch();
    }

    function emergencyWithdraw()
        onlyOwner
        whenPaused
        external
    {
        payroll.emergencyWithdraw();
    }

    function determineAllocation(address[] tokens, uint256[] distribution)
        onlyEmployee
        whenNotPaused
        external
    {
        payroll.determineAllocation(tokens, distribution);
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
