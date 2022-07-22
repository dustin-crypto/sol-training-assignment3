// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IChequeBank} from './interfaces/IChequeBank.sol';

contract ChequeBank is IChequeBank {

  mapping(address => uint) public userBalances;
  mapping(address => Cheque) public userSignedCheque;
  mapping(bytes32 => Cheque) public cheques;
  mapping(bytes32 => bool) public redeemableCheques;

  function deposit() payable override external {
    userBalances[msg.sender] += msg.value;
  }

  function withdraw(uint _amount) override external {
    require(_amount <= userBalances[msg.sender], 'Not enough amount to withdraw');
    userBalances[msg.sender] -= _amount;
    payable(msg.sender).transfer(_amount);
  }

  function withdrawTo(uint _amount, address payable _recipient) override external {
    require(_amount <= userBalances[msg.sender], 'Not enough amount to withdraw');
    userBalances[msg.sender] -= _amount;
    userBalances[_recipient] += _amount;
    _recipient.transfer(_amount);
  }

  function getMessageHash(
    ChequeInfo memory chequeInfo
  ) private view returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        chequeInfo.chequeId,
        msg.sender,
        chequeInfo.payee,
        chequeInfo.amount,
        address(this),
        chequeInfo.validFrom,
        chequeInfo.validThru
      )
    );
  }

  function splitSignature(bytes memory sig) public pure returns(
    bytes32 r,
    bytes32 s,
    uint8 v
  ) {
    require(sig.length == 65, "Invalid signature length");

    assembly {
      /*
        First 32 bytes stores the length of the signature

      add(sig, 32) = pointer of sig + 32
      effectively, skips first 32 bytes of signature

      mload(p) loads next 32 bytes starting at the memory address p into memory
      */

      // first 32 bytes, after the length prefix
      r := mload(add(sig, 32))
      // second 32 bytes
      s := mload(add(sig, 64))
      // final byte (first byte of the next 32 bytes)
      v := byte(0, mload(add(sig, 96)))
    }
  }

  function recoverSigner(bytes32 _message, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
    // prefix hashed message with "\x19Ethereum Signed Message:\n32"
    bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _message));
    return ecrecover(hash, _v, _r, _s);
  }

  function issueCheque(Cheque calldata _newCheque) external {
    ChequeInfo calldata c = _newCheque.chequeInfo;
    (bytes32 r, bytes32 s, uint8 v) = splitSignature(_newCheque.sig);
    require(msg.sender == recoverSigner(getMessageHash(c), v, r, s), 'Not valid signature');

    // store cheque
    Cheque memory newCheque = Cheque(
      ChequeInfo({
        chequeId: c.chequeId,
        payer: msg.sender,
        payee: c.payee,
        amount: c.amount,
        validFrom: c.validFrom,
        validThru: c.validThru
      }),
      _newCheque.sig
    );
    cheques[c.chequeId] = newCheque;
    userSignedCheque[msg.sender] = newCheque;
    redeemableCheques[c.chequeId] = true;
  }

  function getCheque(bytes32 _chequeId) public view returns (Cheque memory) {
    return cheques[_chequeId];
  }

  function redeem(ChequeInfo calldata _chequeData) override external {
    require(_chequeData.payee == msg.sender, "Uncorrect payee");
    if (isChequeValid(_chequeData.payee, _chequeData.chequeId)) {

      // check cheque info from payee is aligned with the correct cheque
      ChequeInfo storage c = cheques[_chequeData.chequeId].chequeInfo;
      require(c.amount == _chequeData.amount, "Wrong Amount");
      require(c.payer == _chequeData.payer, "Wrong payer");
      require(c.validFrom == _chequeData.validFrom, "Wrong validFrom");
      require(c.validThru == _chequeData.validThru, "Wrong validThru");

      // state changes
      redeemableCheques[c.chequeId] = false;
      userBalances[c.payer] -= c.amount;
      userBalances[c.payee] += c.amount;

      // redeem successfully! transfer funds to payee
      payable(c.payee).transfer(c.amount);
    } else {
      revert("Cheque Invalid");
    }
  }

  function revoke(bytes32 _chequeId) override external {
    require(cheques[_chequeId].chequeInfo.payer == msg.sender, "Not the payer");
    require(redeemableCheques[_chequeId], "Already redeemed");
    redeemableCheques[_chequeId] = false;
  }

  function isChequeValid(address payee, bytes32 _chequeId) public view returns(bool) {
    ChequeInfo storage c = cheques[_chequeId].chequeInfo;
    require(cheques[_chequeId].sig.length == 65, "Cheque not exist");
    require(c.payee == payee, "Unmatched cheque and payee");

    if (!redeemableCheques[_chequeId]) {
      return false;
    }

    if (c.amount > userBalances[c.payer]) {
      return false;
    }

    // cheque not valid yet
    if (c.validFrom != 0 && c.validFrom > block.number) {
      return false;
    }

    // cheque expired
    if (c.validThru != 0 && c.validThru < block.number) {
      return false;
    }

    return true;
  }
}
