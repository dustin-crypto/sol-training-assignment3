# sol-training-assignment3

**This project leverages hardhat framework**

this README contains how to run the code

# Task1
located in `task1` directory

# Task2
## Setup

```shell
yarn install
```

## Run test cases

```shell
yarn hardhat compile

yarn hardhat test
```

## Basic workflow
1. A payer can call `issueCheque` to submit a e-cheque with his/her own signature to the contract
2. In the `issueCheque` we will verify the signature with the data payer provided
  - chequeInfoHash: hash the data part
  - (v, r, s): split the input signature
  - recover and verify the payer address with the above hash and (v, r, s)
3. The payer can revoke the cheque by calling `revoke`
4. A payee can check if the cheuque is still valid by calling `isChequeValid`
5. The payee can call `redeem` to redeem the cheque

## Function Test Cases

- deposit
- withdraw
- withdrawTo
- recoverSigner
- splitSignature
- issueCheque
- getCheque
- isChequeValid
- revoke
- redeem
- notifySignOver and redeemSignOver

## Additional Task
- sign-over feature
