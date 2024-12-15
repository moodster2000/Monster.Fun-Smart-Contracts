// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Interface for Monster Token
interface IMonsterToken {
    function inBattle() external view returns (bool);
    function startBattle(address opponent) external;
    function endBattle(address winner, address loser, uint256 transferAmount) external;
}


// Monster Token Contract
contract MonsterToken is ERC20, Ownable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    bool public inBattle;
    uint256 public curveMultiplier = 16000;

    event BattleStarted(address indexed opponent);
    event BattleEnded(address indexed winner, address indexed loser, uint256 transferredValue);
    event Trade(address indexed trader, bool isBuy, uint256 amount, uint256 ethAmount, uint256 protocolFee);

    constructor(
        string memory name,
        string memory symbol,
        address initialOwner,
        address _protocolFeeDestination,
        uint256 _protocolFeePercent
    ) ERC20(name, symbol) Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
        protocolFeeDestination = _protocolFeeDestination;
        protocolFeePercent = _protocolFeePercent;
    }

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * protocolFeePercent) / 1 ether;
    }

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply * (supply + 1) * (2 * supply + 1)) / 6);
        uint256 sum2 = ((supply + amount) * (supply + amount + 1) * (2 * (supply + amount) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / curveMultiplier;
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        return getPrice(totalSupply(), amount);
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        return getPrice(totalSupply() - amount, amount);
    }

    function buyTokens(uint256 amount) public payable {
        require(!inBattle, "Monster is in battle");
        require(amount > 0, "Amount must be greater than 0");

        uint256 price = getBuyPrice(amount);
        uint256 protocolFee = calculateFee(price);
        uint256 totalCost = price + protocolFee;

        require(msg.value >= totalCost, "Insufficient payment");

        _mint(msg.sender, amount);

        emit Trade(msg.sender, true, amount, price, protocolFee);

        (bool success, ) = protocolFeeDestination.call{value: protocolFee}("");
        require(success, "Fee transfer failed");
        
        if (msg.value > totalCost) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - totalCost}("");
            require(refundSuccess, "Refund failed");
        }
    }

    function sellTokens(uint256 amount) public {
        require(!inBattle, "Monster is in battle");
        require(balanceOf(msg.sender) >= amount, "Insufficient tokens");

        uint256 price = getSellPrice(amount);
        uint256 protocolFee = calculateFee(price);
        uint256 payout = price - protocolFee;

        _burn(msg.sender, amount);

        emit Trade(msg.sender, false, amount, price, protocolFee);

        (bool success1, ) = msg.sender.call{value: payout}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        require(success1 && success2, "Transfer failed");
    }

    function adjustCurveMultiplier() internal view returns (uint256) {
        uint256 currentTVL = address(this).balance;
        uint256 currentSupply = totalSupply();
        
        // Using the formula: TVL = n(n+1)(2n+1)/6 * (1/slope)
        // Rearranging to solve for slope
        uint256 formulaNumerator = currentSupply * (currentSupply + 1) * (2 * currentSupply + 1);
        return (formulaNumerator * 1 ether) / (6 * currentTVL);
    }

    function startBattle(address opponent) external onlyOwner {
        require(!inBattle, "Already in battle");
        inBattle = true;
        emit BattleStarted(opponent);
    }

    function endBattle(address winner, address loser, uint256 transferAmount) external onlyOwner {
        require(inBattle, "Not in battle");
        inBattle = false;

        if (winner == address(this)) {
            // Receive value from losing monster
            curveMultiplier = adjustCurveMultiplier();
        } else if (loser == address(this)) {
            // Transfer value to winning monster
            (bool success, ) = winner.call{value: transferAmount}("");
            require(success, "Battle transfer failed");
            curveMultiplier = adjustCurveMultiplier();
        }

        emit BattleEnded(winner, loser, transferAmount);
    }

    receive() external payable {}
}