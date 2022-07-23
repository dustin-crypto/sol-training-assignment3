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

    struct SignOverInfo {
      uint8 counter;
      bytes32 chequeId;
      address oldPayee;
      address newPayee;
    }

    struct Cheque {
        ChequeInfo chequeInfo;
        bytes sig;
    }

    struct SignOver {
      SignOverInfo signOverInfo;
      bytes sig;
    }

    function deposit() payable external;
    function withdraw(uint _amount) external;
    function withdrawTo(uint _amount, address payable _recipient) external;
    function redeem(ChequeInfo calldata _chequeData) external;
    function revoke(bytes32 _chequeId) external;
    function notifySignOver(SignOver calldata _signOverData) external;
    function redeemSignOver(
        Cheque calldata chequeData,
        SignOver[] calldata signOverData
    ) external;
}
