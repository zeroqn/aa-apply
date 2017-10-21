pragma solidity ^0.4.17;

/**
 * @title SharedLibrary
 */

import "zeppelin-solidity/contracts/token/ERC20.sol";


library SharedLibrary {

    function withdrawFrom(address account, address[] _tokens)
        internal
    {
        if (account.balance > 0) {
            msg.sender.transfer(account.balance);
        }

        for (uint i = 0; i < _tokens.length; i++) {
            ERC20 token = ERC20(_tokens[i]);
            uint256 amount = token.balanceOf(account);
            token.transfer(msg.sender, amount);
        }
    }

}
