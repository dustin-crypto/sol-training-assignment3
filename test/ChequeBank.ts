import { expect } from "chai";
import { randomBytes } from "crypto";
import { ethers } from "hardhat";
import { Contract, ContractFactory, BigNumber, utils } from "ethers";

describe("ChequeBank test suite", async () => {
  let ChequeBank: ContractFactory;
  let chequeBank: Contract;
  let user1, user2;
  const makeChequeId = () => {
    return randomBytes(32);
  };
  const getWei = (amount: string): BigNumber => {
    return ethers.utils.parseEther(amount);
  };

  beforeEach(async () => {
    ChequeBank = await ethers.getContractFactory("ChequeBank");
    chequeBank = await ChequeBank.deploy();
    await chequeBank.deployed();
  });

  describe("cheque component", async () => {
    it("generate bytes32 chequeId successfully", () => {
      const id = makeChequeId();
      expect(id.toString("hex").length === 64).to.be.true; // 32 bytes
    });
  });
  describe("function test", async () => {
    it("deposit function", async () => {
      [user1] = await ethers.getSigners();
      const tx = await chequeBank.deposit({ value: 1000 });
      await tx.wait();
      expect(await chequeBank.userBalances(user1.address)).to.equal(1000);
    });

    it("withdraw function", async () => {
      [user1] = await ethers.getSigners();
      let tx = await chequeBank.deposit({ value: getWei("1.0") });
      await tx.wait();
      const user1Balance: BigNumber = await user1.getBalance();

      tx = await chequeBank.withdraw(getWei("0.5"));
      await tx.wait();

      expect((await user1.getBalance()).gt(user1Balance)).to.be.true;
      expect(await chequeBank.userBalances(user1.address)).to.equal(
        getWei("0.5")
      );
      await expect(chequeBank.withdraw(getWei("0.6"))).to.revertedWith(
        "Not enough amount to withdraw"
      );
    });

    it("withdrawTo function", async () => {
      [user1, user2] = await ethers.getSigners();

      let tx = await chequeBank.deposit({ value: getWei("1.0") });
      await tx.wait();

      const user2Balance: BigNumber = await user2.getBalance();
      tx = await chequeBank.withdrawTo(getWei("0.5"), user2.address);
      await tx.wait();

      expect((await user2.getBalance()).gt(user2Balance)).to.be.true;
      expect(await chequeBank.userBalances(user1.address)).to.equal(
        getWei("0.5")
      );
      expect(await chequeBank.userBalances(user2.address)).to.equal(
        getWei("0.5")
      );
    });

    it("recoverSigner function", async () => {
      [user1, user2] = await ethers.getSigners();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );
      const sig = ethers.utils.splitSignature(signature);

      expect(
        await chequeBank.recoverSigner(
          utils.keccak256(concat),
          sig.v,
          sig.r,
          sig.s
        )
      ).to.equal(payer);
    });

    it("splitSignature function", async () => {
      [user1, user2] = await ethers.getSigners();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );
      const sig = ethers.utils.splitSignature(signature);

      const [r, s, v] = await chequeBank.splitSignature(signature);
      expect(r).to.equal(sig.r);
      expect(s).to.equal(sig.s);
      expect(v).to.equal(sig.v);
    });

    it("issueCheque function", async () => {
      [user1, user2] = await ethers.getSigners();

      let tx = await chequeBank.deposit({ value: 20000 });
      await tx.wait();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );

      const makeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 0,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(makeChequeData);
      await tx.wait();

      const storedCheque = await chequeBank.getCheque(id);
      expect(storedCheque.chequeInfo.chequeId).to.equal(utils.hexlify(id));
      expect(storedCheque.chequeInfo.amount).to.equal(BigNumber.from(amount));
      expect(storedCheque.chequeInfo.payer).to.equal(payer);
      expect(storedCheque.chequeInfo.payee).to.equal(payee);
      expect(storedCheque.chequeInfo.validFrom).to.equal(0);
      expect(storedCheque.chequeInfo.validThru).to.equal(0);
      expect(storedCheque.sig).to.equal(signature);
      expect(await chequeBank.redeemableCheques(id)).to.be.true;
    });

    it("getCheque function", async () => {
      [user1, user2] = await ethers.getSigners();

      let tx = await chequeBank.deposit({ value: 20000 });
      await tx.wait();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );

      const makeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 0,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(makeChequeData);
      await tx.wait();

      const storedCheque = await chequeBank.getCheque(id);
      expect(storedCheque.chequeInfo.chequeId).to.equal(utils.hexlify(id));
      expect(storedCheque.chequeInfo.amount).to.equal(BigNumber.from(amount));
      expect(storedCheque.chequeInfo.payer).to.equal(payer);
      expect(storedCheque.chequeInfo.payee).to.equal(payee);
      expect(storedCheque.chequeInfo.validFrom).to.equal(0);
      expect(storedCheque.chequeInfo.validThru).to.equal(0);
      expect(storedCheque.sig).to.equal(signature);
    });

    it("isChequeValid function", async () => {
      [user1, user2] = await ethers.getSigners();

      let tx = await chequeBank.deposit({ value: 20000 });
      await tx.wait();

      let id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      let concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      let signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );

      const makeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 0,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(makeChequeData);
      await tx.wait();

      expect(await chequeBank.isChequeValid(user2.address, id)).to.be.true;
      await expect(chequeBank.isChequeValid(payer, id)).to.be.revertedWith(
        "Unmatched cheque and payee"
      );
      await expect(
        chequeBank.isChequeValid(payer, makeChequeId())
      ).to.be.revertedWith("Cheque not exist");

      // remake
      id = makeChequeId();
      concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(100), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );
      let remakeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 100,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(remakeChequeData);
      await tx.wait();
      expect(await chequeBank.isChequeValid(user2.address, id)).to.be.false;
    });

    it("revoke function", async () => {
      [user1, user2] = await ethers.getSigners();

      // deposit
      let tx = await chequeBank.deposit({ value: 20000 });
      await tx.wait();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );

      const makeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 0,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(makeChequeData);
      await tx.wait();

      expect(await chequeBank.isChequeValid(user2.address, id)).to.be.true;
      expect(await chequeBank.redeemableCheques(id)).to.be.true;

      // revoke
      tx = await chequeBank.revoke(id);
      await tx.wait();

      expect(await chequeBank.redeemableCheques(id)).to.be.false;
    });

    it("redeem function", async () => {
      [user1, user2] = await ethers.getSigners();

      // deposit
      let tx = await chequeBank.deposit({ value: 20000 });
      await tx.wait();

      const id = makeChequeId();
      const payer = user1.address;
      const payee = user2.address;
      const amount = 1000;

      const concat = ethers.utils.hexConcat([
        id,
        payer,
        payee,
        utils.hexZeroPad(utils.hexlify(amount), 32),
        chequeBank.address,
        utils.hexZeroPad(utils.hexlify(0), 4),
        utils.hexZeroPad(utils.hexlify(0), 4),
      ]);
      const signature = await user1.signMessage(
        utils.arrayify(utils.keccak256(concat))
      );

      const makeChequeData = {
        chequeInfo: {
          chequeId: id,
          payer,
          payee,
          amount,
          validFrom: 0,
          validThru: 0,
        },
        sig: signature,
      };
      tx = await chequeBank.issueCheque(makeChequeData);
      await tx.wait();

      expect(await chequeBank.isChequeValid(user2.address, id)).to.be.true;
      expect(await chequeBank.redeemableCheques(id)).to.be.true;

      // redeem
      let remakeInvalidChequeData = {
        chequeId: id,
        payer,
        payee,
        amount: amount + 1000,
        validFrom: 0,
        validThru: 0,
      };
      await expect(
        chequeBank.connect(user2).redeem(remakeInvalidChequeData)
      ).to.be.revertedWith("Wrong Amount");

      remakeInvalidChequeData = {
        chequeId: id,
        payer,
        payee,
        amount,
        validFrom: 100,
        validThru: 0,
      };
      await expect(
        chequeBank.connect(user2).redeem(remakeInvalidChequeData)
      ).to.be.revertedWith("Wrong validFrom");

      remakeInvalidChequeData = {
        chequeId: id,
        payer,
        payee,
        amount,
        validFrom: 100,
        validThru: 0,
      };
      await expect(
        chequeBank.redeem(remakeInvalidChequeData)
      ).to.be.revertedWith("Uncorrect payee");

      remakeInvalidChequeData = {
        chequeId: id,
        payer: user2.address,
        payee,
        amount,
        validFrom: 100,
        validThru: 0,
      };
      await expect(
        chequeBank.connect(user2).redeem(remakeInvalidChequeData)
      ).to.be.revertedWith("Wrong payer");

      // successfully redeemed
      const remakeChequeData = {
        chequeId: id,
        payer,
        payee,
        amount,
        validFrom: 0,
        validThru: 0,
      };
      tx = await chequeBank.connect(user2).redeem(remakeChequeData);
      await tx.wait();

      expect(await chequeBank.redeemableCheques(id)).to.be.false;
      expect(await chequeBank.userBalances(payer)).to.equal(19000);
      expect(await chequeBank.userBalances(payee)).to.equal(1000);
    });
  });
});
