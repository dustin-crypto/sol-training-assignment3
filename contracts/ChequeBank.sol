// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IChequeBank} from './interfaces/IChequeBank.sol';

contract ChequeBank is IChequeBank {

  bytes4 constant signOverHeader = 0xFFFFDEAD;
  mapping(address => uint) public userBalances;
  mapping(bytes32 => Cheque) public cheques;
  mapping(bytes32 => bool) public redeemableCheques;
  mapping(bytes32 => uint) public chequeSignOverCounter;
  mapping(bytes32 => SignOver[]) public chequeSignOverList;

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

  function getSignOverMessageHash(
    SignOverInfo memory signOverInfo
  ) private pure returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        signOverHeader,
        signOverInfo.counter,
        signOverInfo.chequeId,
        signOverInfo.oldPayee,
        signOverInfo.newPayee
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
    require(chequeSignOverCounter[_chequeId] == 0, "Has been signedOver");
    redeemableCheques[_chequeId] = false;
  }

  function notifySignOver(SignOver calldata _signOverData) override external {
    SignOverInfo calldata signOver = _signOverData.signOverInfo;
    (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signOverData.sig);
    require(msg.sender == recoverSigner(getSignOverMessageHash(signOver), v, r, s), 'Not valid signature');
    require(signOver.counter < 6, "Exceed sign-over limit");
    require(redeemableCheques[signOver.chequeId], "Redeemed or Revoked");

    // store SignOver
    SignOver memory newSignOver = SignOver(
      SignOverInfo({
        counter: signOver.counter,
        chequeId: signOver.chequeId,
        oldPayee: signOver.oldPayee,
        newPayee: signOver.newPayee
      }),
      _signOverData.sig
    );

    // sign-over counter + 1
    chequeSignOverCounter[signOver.chequeId]++;

    // change payee on this cheque
    cheques[signOver.chequeId].chequeInfo.payee = signOver.newPayee;

    // store sign over data
    chequeSignOverList[signOver.chequeId].push(newSignOver);
  }

  function redeemSignOver(
    Cheque calldata _chequeData,
    SignOver[] calldata _signOverData
  ) override external {
    // check all data
    bytes32 id = _chequeData.chequeInfo.chequeId;
    Cheque storage c = cheques[id];
    require(keccak256(c.sig) == keccak256(_chequeData.sig) &&
            c.chequeInfo.chequeId == _chequeData.chequeInfo.chequeId &&
            c.chequeInfo.payer == _chequeData.chequeInfo.payer &&
            c.chequeInfo.payee == _chequeData.chequeInfo.payee &&
            c.chequeInfo.amount == _chequeData.chequeInfo.amount && 
            c.chequeInfo.validFrom == _chequeData.chequeInfo.validFrom &&
            c.chequeInfo.validThru == _chequeData.chequeInfo.validThru, "Cheque data not valid");
    SignOver[] storage s = chequeSignOverList[id];
    for (uint256 i = 0; i < _signOverData.length; i++) {
      require(keccak256(s[i].sig) == keccak256(_signOverData[i].sig) &&
              s[i].signOverInfo.chequeId == _signOverData[i].signOverInfo.chequeId &&
              s[i].signOverInfo.counter == _signOverData[i].signOverInfo.counter &&
              s[i].signOverInfo.oldPayee == _signOverData[i].signOverInfo.oldPayee &&
              s[i].signOverInfo.newPayee == _signOverData[i].signOverInfo.newPayee, "Sign-over data not valid");
    }

    // redeem successfully! transfer funds to payee
    userBalances[msg.sender] += c.chequeInfo.amount;
    payable(msg.sender).transfer(100);
  }

  function isChequeValid(address payee, bytes32 _chequeId) public view returns(bool) {
    ChequeInfo storage c = cheques[_chequeId].chequeInfo;
    require(cheques[_chequeId].sig.length == 65, "Cheque not exist");
    require(c.payee == payee, "Unmatched cheque and payee");

    if (!redeemableCheques[_chequeId]) {
      return false;
    }

    // check payer balances in this contract
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
