// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WATER is ERC20 {
    constructor(uint256 initialSupply) ERC20("WaterToken", "WATER") {
        _mint(msg.sender, initialSupply);
    }
}

contract MELON is ERC20 {
    constructor(uint256 initialSupply) ERC20("MelonToken", "MELON") {
        _mint(msg.sender, initialSupply);
    }
}

contract FruitStand {

    struct UserStake {
        uint startBlock;
        uint stakeAmount;
    }

    ERC20 water;
    ERC20 melon;
    mapping (address => UserStake) userStakes;

    constructor(address _water, address _melon) {
        water = ERC20(_water);
        melon = ERC20(_melon);
    }

    function stake(uint _amount) external {
        require(_amount > 0, "FruitStand: Stake amount must be greater than zero");
        if (userStakes[msg.sender].startBlock != 0) {
            // Pay out current stake
            payout(msg.sender, userStakes[msg.sender]);
        }
        water.transferFrom(msg.sender, address(this), _amount);
        userStakes[msg.sender] = UserStake({ startBlock: block.number, stakeAmount: _amount });
    }

    function unstake() external {
        require(userStakes[msg.sender].startBlock != 0, "FruitStand: User have not staked");
        UserStake storage a = userStakes[msg.sender];
        a.startBlock = 0;
        a.stakeAmount = 0;
        payout(msg.sender, userStakes[msg.sender]);
        water.transfer(msg.sender, userStakes[msg.sender].stakeAmount);
    }

    function payout(address user, UserStake storage stake) internal returns (uint8 errCode) {
        uint blockDelta = block.number - stake.startBlock;
        if (blockDelta > 300) {
            blockDelta = 300;
        }
        uint rewardAmount = fib(blockDelta) * stake.stakeAmount;
        melon.transfer(user, rewardAmount);
        return 0;
    }

    function fib(uint n) private pure returns (uint b) {
        if (n == 0) {
            return 0;   
        }
        uint a = 1;
        b = 1;
        for (uint i = 2; i < n; i++) {
            uint c = a + b;
            a = b;
            b = c;
        }
        return b;
    }
}
