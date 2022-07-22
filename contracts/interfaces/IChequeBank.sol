// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChequeBank {

    struct ChequeInfo {
        uint amount;
        bytes32 chequeId;
        uint32 validFrom;
        uint32 validThru;
        address payee;
        address payer;
    }

    struct Cheque {
        ChequeInfo chequeInfo;
        bytes sig;
    }

    function deposit() payable external;
    function withdraw(uint _amount) external;
    function withdrawTo(uint _amount, address payable _recipient) external;
    function redeem(ChequeInfo memory _chequeData) external;
    function revoke(bytes32 _chequeId) external;
}
