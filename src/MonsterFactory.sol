// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MonsterToken.sol";

// Factory Contract
contract MonsterFactory is Ownable, ReentrancyGuard, Pausable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    
    mapping(address => bool) public isWhitelisted;
    mapping(address => address) public creatorToToken;
    mapping(address => bool) public isMonsterToken;
    
    event TokenCreated(address indexed creator, address tokenAddress, string name, string symbol);
    event AddressWhitelisted(address indexed user, bool status);
    
    constructor(
        address _protocolFeeDestination,
        uint256 _protocolFeePercent
    ) Ownable(msg.sender) {
        protocolFeeDestination = _protocolFeeDestination;
        protocolFeePercent = _protocolFeePercent;
    }

    function setWhitelistStatus(address user, bool status) external onlyOwner {
        isWhitelisted[user] = status;
        emit AddressWhitelisted(user, status);
    }

    function batchSetWhitelist(address[] calldata users, bool status) external onlyOwner {
        for(uint i = 0; i < users.length; i++) {
            isWhitelisted[users[i]] = status;
            emit AddressWhitelisted(users[i], status);
        }
    }
    
    function createMonsterToken(
        string memory name,
        string memory symbol
    ) external nonReentrant whenNotPaused {
        require(isWhitelisted[msg.sender], "Address not whitelisted");
        require(creatorToToken[msg.sender] == address(0), "Already created a token");
        
        MonsterToken token = new MonsterToken(
            name,
            symbol,
            owner(),
            protocolFeeDestination,
            protocolFeePercent
        );
        
        creatorToToken[msg.sender] = address(token);
        isMonsterToken[address(token)] = true;
        
        emit TokenCreated(msg.sender, address(token), name, symbol);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

//edits 
//add function to change protocol fee destination 
//not sure if an event is needed for whitelisted address 