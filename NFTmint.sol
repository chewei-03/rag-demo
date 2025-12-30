// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/**
 * @title SimpleRAGNFT
 * @dev 简化版 RAG NFT 合约，只处理核心铸造逻辑 + 三大扩展功能
 */
contract SimpleRAGNFT is ERC721, Ownable, ERC2981 {
    using Strings for uint256;
    
    // ============== 核心结构 ==============
    struct RAGInfo {
        string contextCID;      // IPFS CID (RAG检索上下文)
        string metadataHash;    // 元数据哈希
        string kgNodeId;        // 知识图谱节点ID
        uint256 score;          // 检索质量评分 (0-100)
        uint256 timestamp;      // 创建时间
        address creator;        // 创建者
        string modelVersion;    // Self-RAG 模型版本
    }
    
    // ============== 状态变量 ==============
    uint256 private _tokenIdCounter;
    string private _baseTokenURI;
    
    // 核心映射
    mapping(uint256 => RAGInfo) public ragInfo;
    mapping(string => bool) public usedCIDs;  // 防重复铸造
    
    // ============== 扩展1：版税机制 ==============
    address private _royaltyReceiver;
    uint96 private _royaltyBasisPoints = 500; // 5% 版税
    
    // ============== 扩展2：质押机制 ==============
    struct StakeInfo {
        uint256 amount;         // 质押金额
        uint256 stakedAt;       // 质押时间
        uint256 lockPeriod;     // 锁定期
    }
    
    mapping(uint256 => StakeInfo) public stakes;
    uint256 public totalStaked;
    
    // ============== 扩展3：跨链准备 ==============
    uint32 public chainId;      // 当前链ID
    address public bridge;      // 跨链桥地址
    
    // ============== 事件 ==============
    event RAGNFTCreated(
        uint256 indexed tokenId,
        address indexed creator,
        string indexed kgNodeId,
        string contextCID,
        uint256 score
    );
    
    event Staked(
        uint256 indexed tokenId,
        address indexed staker,
        uint256 amount,
        uint256 lockPeriod
    );
    
    event Unstaked(
        uint256 indexed tokenId,
        address indexed staker,
        uint256 amount
    );
    
    // ============== 构造函数 ==============
    constructor(
        string memory baseURI,
        address royaltyReceiver,
        uint32 _chainId
    ) ERC721("RAG Knowledge NFT", "RAGNFT") Ownable(msg.sender) {
        _baseTokenURI = baseURI;
        _tokenIdCounter = 1;
        
        // 版税设置
        _royaltyReceiver = royaltyReceiver;
        _setDefaultRoyalty(royaltyReceiver, _royaltyBasisPoints);
        
        // 跨链准备
        chainId = _chainId;
    }
    
    // ============== 核心铸造函数（简化版） ==============
    /**
     * @dev 铸造RAG NFT - 只需提供链下计算好的数据
     * @param contextCID IPFS CID (Self-RAG的上下文)
     * @param metadataHash 元数据哈希
     * @param kgNodeId 知识图谱节点ID
     * @param score 质量评分
     * @param modelVersion Self-RAG模型版本
     */
    function mintRAGNFT(
        string memory contextCID,
        string memory metadataHash,
        string memory kgNodeId,
        uint256 score,
        string memory modelVersion
    ) public returns (uint256) {
        // 基本验证
        require(bytes(contextCID).length > 0, "CID required");
        require(!usedCIDs[contextCID], "Content already minted");
        require(bytes(kgNodeId).length > 0, "KG Node ID required");
        require(score <= 100, "Invalid score");
        
        // 生成NFT
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);
        
        // 存储RAG信息
        ragInfo[tokenId] = RAGInfo({
            contextCID: contextCID,
            metadataHash: metadataHash,
            kgNodeId: kgNodeId,
            score: score,
            timestamp: block.timestamp,
            creator: msg.sender,
            modelVersion: modelVersion
        });
        
        // 更新状态
        usedCIDs[contextCID] = true;
        
        emit RAGNFTCreated(tokenId, msg.sender, kgNodeId, contextCID, score);
        
        return tokenId;
    }
    
    // ============== 扩展1：版税功能 ==============
    
    /**
     * @dev 设置版税接收者和比例
     * @param receiver 版税接收地址
     * @param basisPoints 版税百分比 (100 = 1%)
     */
    function setRoyalty(address receiver, uint96 basisPoints) public onlyOwner {
        require(basisPoints <= 1000, "Royalty too high"); // 最大10%
        _royaltyReceiver = receiver;
        _setDefaultRoyalty(receiver, basisPoints);
    }
    
    /**
     * @dev 为单个NFT设置特定版税
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 basisPoints
    ) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, basisPoints);
    }
    
    // ============== 扩展2：质押功能 ==============
    
    /**
     * @dev 质押NFT（证明其质量）
     * @param tokenId NFT ID
     * @param lockDays 锁定天数
     */
    function stakeNFT(uint256 tokenId, uint256 lockDays) public payable {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(msg.value > 0, "Stake amount required");
        require(stakes[tokenId].amount == 0, "Already staked");
        require(lockDays >= 7, "Min 7 days lock");
        
        stakes[tokenId] = StakeInfo({
            amount: msg.value,
            stakedAt: block.timestamp,
            lockPeriod: lockDays * 1 days
        });
        
        totalStaked += msg.value;
        
        emit Staked(tokenId, msg.sender, msg.value, lockDays);
    }
    
    /**
     * @dev 解除质押
     * @param tokenId NFT ID
     */
    function unstakeNFT(uint256 tokenId) public {
        StakeInfo memory stake = stakes[tokenId];
        require(stake.amount > 0, "Not staked");
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(
            block.timestamp >= stake.stakedAt + stake.lockPeriod,
            "Still locked"
        );
        
        uint256 amount = stake.amount;
        
        // 清理质押记录
        delete stakes[tokenId];
        totalStaked -= amount;
        
        // 返回质押资金
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Unstaked(tokenId, msg.sender, amount);
    }
    
    /**
     * @dev 获取质押奖励（简化版 - 实际需要更复杂的经济模型）
     */
    function calculateReward(uint256 tokenId) public view returns (uint256) {
        StakeInfo memory stake = stakes[tokenId];
        if (stake.amount == 0) return 0;
        
        // 简单奖励：年化5%
        uint256 stakedTime = block.timestamp - stake.stakedAt;
        uint256 reward = (stake.amount * 5 * stakedTime) / (100 * 365 days);
        
        return reward;
    }
    
    // ============== 扩展3：跨链功能准备 ==============
    
    /**
     * @dev 设置跨链桥地址
     */
    function setBridge(address bridgeAddress) public onlyOwner {
        bridge = bridgeAddress;
    }
    
    /**
     * @dev 为跨链锁定NFT
     */
    function lockForBridge(uint256 tokenId) public {
        require(msg.sender == bridge, "Only bridge can lock");
        _transfer(ownerOf(tokenId), bridge, tokenId);
    }
    
    /**
     * @dev 从跨链解锁NFT
     */
    function unlockFromBridge(address to, uint256 tokenId) public {
        require(msg.sender == bridge, "Only bridge can unlock");
        _transfer(bridge, to, tokenId);
    }
    
    /**
     * @dev 生成跨链消息哈希（用于验证）
     */
    function getCrossChainHash(uint256 tokenId) public view returns (bytes32) {
        RAGInfo memory info = ragInfo[tokenId];
        return keccak256(abi.encodePacked(
            chainId,
            tokenId,
            info.contextCID,
            info.kgNodeId,
            info.creator
        ));
    }
    
    // ============== 查询函数 ==============
    
    /**
     * @dev 获取NFT的完整信息
     */
    function getNFTInfo(uint256 tokenId) public view returns (
        address owner,
        RAGInfo memory info,
        StakeInfo memory stake,
        uint256 reward
    ) {
        owner = ownerOf(tokenId);
        info = ragInfo[tokenId];
        stake = stakes[tokenId];
        reward = calculateReward(tokenId);
    }
    
    /**
     * @dev 验证内容唯一性
     */
    function isCIDUsed(string memory cid) public view returns (bool) {
        return usedCIDs[cid];
    }
    
    /**
     * @dev 根据知识图谱节点查询NFT
     */
    function getTokenByKGNode(string memory kgNodeId) public view returns (uint256) {
        // 注意：实际生产需要维护反向映射
        // 这里简化处理，需要遍历或额外数据结构
        for (uint256 i = 1; i < _tokenIdCounter; i++) {
            if (ownerOf(i) != address(0) && 
                keccak256(bytes(ragInfo[i].kgNodeId)) == keccak256(bytes(kgNodeId))) {
                return i;
            }
        }
        return 0;
    }
    
    // ============== 元数据和接口支持 ==============
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "NFT does not exist");
        
        RAGInfo memory info = ragInfo[tokenId];
        return string(
            abi.encodePacked(
                _baseTokenURI,
                tokenId.toString(),
                "?cid=", info.contextCID,
                "&kg=", info.kgNodeId,
                "&score=", info.score.toString()
            )
        );
    }
    
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseTokenURI = newBaseURI;
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return 
            ERC721.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }
    
    // ============== 管理员功能 ==============
    
    /**
     * @dev 提取质押池资金（仅用于奖励分发）
     */
    function withdrawStakingPool(uint256 amount) public onlyOwner {
        require(amount <= address(this).balance - totalStaked, "Insufficient funds");
        (bool success,) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev 紧急停止质押功能
     */
    function emergencyUnstake(uint256 tokenId) public onlyOwner {
        StakeInfo memory stake = stakes[tokenId];
        require(stake.amount > 0, "Not staked");
        
        address tokenOwner = ownerOf(tokenId);
        uint256 amount = stake.amount;
        
        delete stakes[tokenId];
        totalStaked -= amount;
        
        (bool success, ) = tokenOwner.call{value: amount}("");
        require(success, "Transfer failed");
    }
}