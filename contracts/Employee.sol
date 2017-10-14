pragma solidity ^0.4.15;

/**
 * @title Employee
 * @dev Employee contract provides functions for handling employees list.
 */

import "./EmployeeLibrary.sol";

import "zeppelin-solidity/contracts/ownership/Ownable.sol";

contract Employee is Ownable {

    using EmployeeLibrary for EmployeeLibrary.EmployeeList;

    EmployeeLibrary.EmployeeList public list;

    function getEmployeeCount()
        external constant returns (uint256)
    {
        return list.getEmployeeCount();
    }

    function getEmployee(uint256 employeeId)
        external constant returns (uint256 id,
                                   bool    active,
                                   address account,
                                   uint256 yearlyUSDSalary,
                                   uint256 lastPayday)
    {
        return list.getEmployee(employeeId);
    }

    function addEmployee(
        address   accountAddress,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    )
        onlyOwner
        external
    {
        list.addEmployee(accountAddress, allowedTokens, initialYearlyUSDSalary);
    }

    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary)
        onlyOwner
        external
    {
        list.setEmployeeSalary(employeeId, yearlyUSDSalary);
    }

    function removeEmployee(uint256 employeeId)
        onlyOwner
        external
    {
        list.removeEmployee(employeeId);
    }

}
