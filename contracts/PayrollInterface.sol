pragma solidity ^0.4.15;

/**
 * @title PayrollInterface
 * @dev This abstract contract acts as interface for Payroll contract. It
 * defines function signatures that are used in Payroll contract.
 * @notice For the sake of simplicity, here we assume USD is a ERC20 token.
 * Also lets assume we can 100% trust the exchange rate oracle.
 */

contract PayrollInterface {

    /* OWNER ONLY */
    function addEmployee(
        address   accountAddress,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    );
    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary);
    function removeEmployee(uint256 employeeId);

    function addFunds() payable;
    function escapeHatch();
    // TODO: Use approveAndCall or ERC223 tokenFallback
    // function addTokenFunds()

    function getEmployeeCount() constant returns (uint256);
    function getEmployee(uint256 employeeId)
        constant returns (bool    active,
                          address employee,
                          uint256 yearlyUSDSalary);

    // @dev Monthly USD amount spent in salaries
    function calculatePayrollBurnrate() constant returns (uint256);
    // @dev Days until the contract can run out of funds
    function calculatePayrollRunway() constant returns (uint256);

    /* EMPLOYEE ONLY */
    // @notice Only callable once every 6 months
    function determineAllocation(address[] tokens, uint256[] distribution);
    // @notice Only callable once a month
    function payday();

    /* ORACLE ONLY */
    // @dev Uses decimals from token
    function setExchangeRate(address token, uint256 usdExchangeRate);

}
