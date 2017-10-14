pragma solidity ^0.4.15;

/**
 * @title EmployeeLibrary
 * @dev This library implement most of logic for Employee contract
 */

import "./PayrollDB.sol";

import "zeppelin-solidity/contracts/math/SafeMath.sol";

// TODO: getAllowedTokens()
library EmployeeLibrary {

    using SafeMath for uint256;

    event OnEmployeeAdded(
        uint256 indexed employeeId,
        address account,
        uint256 indexed yearlyUSDSalary
    );
    event OnEmployeeSalaryUpdated(
        uint256 indexed employeeId,
        uint256 indexed yearlyUSDSalary
    );
    event OnEmployeeRemoved(
        uint256 indexed employeeId
    );

    function isEmployee(address _db)
        internal constant returns (bool)
    {
        PayrollDB db = PayrollDB(_db);

        uint256 employeeId = db.getUIntValue(keyHash("/id", msg.sender));
        if (employeeId == 0) {
            return false;
        }

        // isn't active
        if (!db.getBooleanValue(keyHash("/active", employeeId))) {
            return false;
        }

        return true;
    }

    function getEmployeeCount(address db)
        internal constant returns (uint256)
    {
        return PayrollDB(db).getUIntValue(keyHash("/count"));
    }

    function getEmployeeId(address db, address account)
        internal constant returns (uint256)
    {
        return PayrollDB(db).getUIntValue(keyHash("/id", account));
    }

    function getEmployee(address _db, uint256 employeeId)
        internal constant returns (bool    active,
                                   address account,
                                   uint256 monthlyUSDSalary,
                                   uint256 yearlyUSDSalary)
    {
        PayrollDB db = PayrollDB(_db);

        active = db.getBooleanValue(keyHash("/active", employeeId));
        account = db.getAddressValue(keyHash("/account", employeeId));
        monthlyUSDSalary = db.getUIntValue(
            keyHash("/monthlyUSDSalary", employeeId)
        );
        yearlyUSDSalary = db.getUIntValue(
            keyHash("/yearlyUSDSalary", employeeId)
        );

        return (active, account, monthlyUSDSalary, yearlyUSDSalary);
    }

    function getUSDMonthlySalaries(address db)
        internal constant returns (uint256)
    {
        return PayrollDB(db).getUIntValue(keyHash("/USDMonthlySalaries"));
    }

    function getEmployeeTokens(address _db, uint256 employeeId)
        internal constant returns (address[] tokens)
    {
        PayrollDB db = PayrollDB(_db);
        uint256 count = db.getUIntValue(keyHash("/tokens/count", employeeId));
        uint256 nonce = db.getUIntValue(keyHash("/tokens/nonce", employeeId));
        tokens = new address[](count);

        for (uint i = 0; i < tokens.length; i++) {
            tokens[i] = db.getAddressValue(
                keyHash("/tokens", employeeId, nonce, i)
            );
        }

        return tokens;
    }

    function getEmployeeTokensAlloc(
        address _db,
        uint256 employeeId
    )
        internal constant returns (uint256[] allocation)
    {
        PayrollDB db = PayrollDB(_db);
        uint256 nonce = db.getUIntValue(
            keyHash("/tokens/alloc/nonce", employeeId)
        );
        var tokens = getEmployeeTokens(_db, employeeId);
        allocation = new uint256[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            allocation[i] = db.getUIntValue(
                keyHash("/tokens/alloc", employeeId, nonce, tokens[i])
            );
        }

        return allocation;
    }

    function addEmployee(
        address   _db,
        address   account,
        address[] allowedTokens,
        uint256   initialYearlyUSDSalary
    )
        internal
    {
        require(account != 0x0);
        require(initialYearlyUSDSalary > 0);
        for (uint i = 0; i < allowedTokens.length; i++) {
            require(allowedTokens[i] != 0x0);
        }

        PayrollDB db = PayrollDB(_db);

        updateUSDMonthlySalaries(db, 0, initialYearlyUSDSalary);

        uint256 id = nextId(db);
        db.setBooleanValue(keyHash("/active", id), true);
        db.setAddressValue(keyHash("/account", id), account);
        setAllowedTokens(db, id, allowedTokens);
        db.setUIntValue(keyHash("/yearlyUSDSalary", id),initialYearlyUSDSalary);
        db.setUIntValue(keyHash("/id", account), id);
        OnEmployeeAdded(id, account, initialYearlyUSDSalary);
    }

    function setEmployeeSalary(
        address db,
        uint256 employeeId,
        uint256 yearlyUSDSalary
    )
        internal
    {
        require(employeeId > 0);
        require(yearlyUSDSalary > 0);

        updateUSDMonthlySalaries(db, employeeId, yearlyUSDSalary);
        PayrollDB(db).setUIntValue(
            keyHash("/yearlyUSDSalary", employeeId), yearlyUSDSalary
        );
        OnEmployeeSalaryUpdated(employeeId, yearlyUSDSalary);
    }

    function removeEmployee(address db, uint256 employeeId)
        internal
    {
        require(employeeId > 0);

        PayrollDB(db).setBooleanValue(keyHash("/active", employeeId), false);
        OnEmployeeRemoved(employeeId);
    }

    /// @dev Set employee
    function setEmployeeTokenAllocation(
        address   _db,
        address[] tokens,
        uint256[] distribution
    )
        internal
    {
        uint256 SIX_MONTHS = 4 weeks * 6;

        PayrollDB db = PayrollDB(_db);
        uint256 distSum = 0;
        uint256 employeeId = db.getUIntValue(keyHash("/id", msg.sender));
        uint256 nonce = db.getUIntValue(keyHash("/tokens/nonce", employeeId));
        uint256 nextAllocTime = db.getUIntValue(
            keyHash("/tokens/nextAllocTime", employeeId)
        );

        require(now > nextAllocTime);
        require(tokens.length == distribution.length);
        for (uint i = 0; i < tokens.length; i++) {
            // token should be listed
            require(db.getBooleanValue(
                keyHash("/tokens", employeeId, nonce, tokens[i])
            ));
            // single dist should not exceed 100
            require(distribution[i] <= 100);
            distSum = distSum.add(distribution[i]);
        }
        require(distSum <= 100);

        // update next allocation time
        if (nextAllocTime == 0) {
            // first time
            nextAllocTime = now;
        }
        nextAllocTime = nextAllocTime.add(SIX_MONTHS);
        db.setUIntValue(
            keyHash("/tokens/nextAllocTime", employeeId), nextAllocTime
        );

        setTokensAllocation(_db, employeeId, tokens, distribution);
    }

    function keyHash(string property)
        private constant returns (bytes32)
    {
        return keccak256("/Employee", property);
    }

    function keyHash(string property, uint id)
        private constant returns (bytes32)
    {
        return keccak256("/Employee", id, property);
    }

    function keyHash(string property, address account)
        private constant returns (bytes32)
    {
        return keccak256("/Employee", account, property);
    }

    function keyHash(string property, uint256 id, uint256 nonce, uint idx)
        private constant returns (bytes32)
    {
        return keccak256("/Employee", id, property, nonce, idx);
    }

    function keyHash(string property, uint256 id, uint256 nonce, address addr)
        private constant returns (bytes32)
    {
        return keccak256("/Employee", id, property, nonce, addr);
    }

    function nextId(address db)
        private returns (uint256)
    {
        return PayrollDB(db).addUIntValue(keyHash("/count"), 1);
    }

    function setAllowedTokens(
        address   _db,
        uint256   employeeId,
        address[] tokens
    )
        private
    {
        PayrollDB db = PayrollDB(_db);
        // also update nonce
        uint256 nonce = db.addUIntValue(
            keyHash("/tokens/nonce", employeeId), 1
        );

        db.setUIntValue(keyHash("/tokens/count", employeeId), tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            db.setAddressValue(
                keyHash("/tokens", employeeId, nonce, i), tokens[i]
            );
            db.setBooleanValue(
                keyHash("/tokens", employeeId, nonce, tokens[i]), true
            );
        }
    }

    function setTokensAllocation(
        address   _db,
        uint256   employeeId,
        address[] tokens,
        uint256[] distribution
    )
        private
    {
        PayrollDB db = PayrollDB(_db);

        // also update nonce
        uint256 nonce = db.addUIntValue(
            keyHash("/tokens/alloc/nonce", employeeId), 1
        );
        for (uint i = 0; i < tokens.length; i++) {
            db.setUIntValue(
                keyHash("/tokens/alloc", employeeId, nonce, tokens[i]),
                distribution[i]
            );
        }
    }

    function updateUSDMonthlySalaries(
        address _db,
        uint256 employeeId,
        uint256 yearlyUSDSalary
    )
        private
    {
        require(yearlyUSDSalary % 12 == 0);

        PayrollDB db = PayrollDB(_db);

        uint256 usdMonthlySalaries = db.getUIntValue(
            keyHash("/USDMonthlySalaries")
        );
        uint256 monthlyUSDSalary = yearlyUSDSalary.div(12);

        if (employeeId != 0) {
            // for exist employee, subtract previous monthly salary
            // then add updated one.
            uint256 preMonthlySalary = db.getUIntValue(
                keyHash("/monthlyUSDSalary", employeeId)
            );
            usdMonthlySalaries = usdMonthlySalaries.sub(preMonthlySalary);
        }

        usdMonthlySalaries = usdMonthlySalaries.add(monthlyUSDSalary);
        db.setUIntValue(keyHash("/USDMonthlySalaries"), usdMonthlySalaries);
        db.setUIntValue(
            keyHash("/monthlyUSDSalary", employeeId), monthlyUSDSalary
        );
    }

}
