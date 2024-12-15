// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MonsterFactory.sol";
import "./MonsterToken.sol";
contract BattleManager is Ownable, ReentrancyGuard {
    MonsterFactory public immutable factory;
    
    struct Battle {
        address monster1;
        address monster2;
        uint256 startTime;
        bytes32 battleId;
        bool processed;
    }
    
    mapping(address => bool) public isValidator;
    mapping(bytes32 => Battle) public battles;
    
    uint256 public constant BATTLE_TIMEOUT = 5 minutes;
    uint256 public constant BATTLE_VALUE_PERCENT = 5;
    
    event BattleInitiated(bytes32 indexed battleId, address indexed monster1, address indexed monster2);
    event BattleResolved(bytes32 indexed battleId, address indexed winner, address indexed loser, uint256 transferredValue);
    event ValidatorUpdated(address validator, bool status);

    modifier onlyValidator() {
        require(isValidator[msg.sender], "Only validator");
        _;
    }

    constructor(address _factory) Ownable(msg.sender) {
        factory = MonsterFactory(_factory);
    }

    function setValidator(address validator, bool status) external onlyOwner {
        isValidator[validator] = status;
        emit ValidatorUpdated(validator, status);
    }

    function initiateBattle(address payable monster1, address payable monster2) external onlyValidator returns (bytes32 battleId) {
        require(factory.isMonsterToken(monster1) && factory.isMonsterToken(monster2), "Invalid monsters");
        require(!IMonsterToken(monster1).inBattle() && !IMonsterToken(monster2).inBattle(), "Monster in battle");

        battleId = keccak256(abi.encodePacked(monster1, monster2, block.timestamp, block.number));
        
        battles[battleId] = Battle({
            monster1: monster1,
            monster2: monster2,
            startTime: block.timestamp,
            battleId: battleId,
            processed: false
        });

        IMonsterToken(monster1).startBattle(monster2);
        IMonsterToken(monster2).startBattle(monster1);

        emit BattleInitiated(battleId, monster1, monster2);
        
        return battleId;
    }

    function resolveBattle(bytes32 battleId, address payable winner, address payable loser) external onlyValidator nonReentrant {
        Battle storage battle = battles[battleId];
        require(!battle.processed, "Battle already processed");
        require(block.timestamp <= battle.startTime + BATTLE_TIMEOUT, "Battle timeout");
        require(
            (winner == battle.monster1 && loser == battle.monster2) ||
            (winner == battle.monster2 && loser == battle.monster1),
            "Invalid battle participants"
        );

        battle.processed = true;

        uint256 loserBalance = address(loser).balance;
        uint256 transferAmount = (loserBalance * BATTLE_VALUE_PERCENT) / 100;

        IMonsterToken(winner).endBattle(winner, loser, transferAmount);
        IMonsterToken(loser).endBattle(winner, loser, transferAmount);

        emit BattleResolved(battleId, winner, loser, transferAmount);
    }

    function resolveBattleTimeout(bytes32 battleId) external {
        Battle storage battle = battles[battleId];
        require(!battle.processed, "Battle already processed");
        require(block.timestamp > battle.startTime + BATTLE_TIMEOUT, "Battle not timed out");

        IMonsterToken(battle.monster1).endBattle(address(0), address(0), 0);
        IMonsterToken(battle.monster2).endBattle(address(0), address(0), 0);
        
        battle.processed = true;
    }
}