// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * 文件包含 5 个合约（外加 1 个接口）：
 * 1) UtilityToken (ERC20-like)
 * 2) GovernanceToken (ERC20-like + Minter role)
 * 3) ReputationManager
 * 4) ArbitrationContract
 * 5) TaskManager
 * 6) KnowledgeNFT (ERC721-like + 购买访问 + 分账)
 *
 * 说明：为方便 Remix 单文件部署，本实现不依赖 OpenZeppelin。
 * 生产环境建议替换为 OpenZeppelin ERC20/ERC721/Ownable/ReentrancyGuard。
 */

/* ----------------------------- Common Ownable ----------------------------- */
abstract contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero addr");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/* ----------------------------- ERC20-like Token --------------------------- */
contract UtilityToken is Ownable {
    string public name = "UtilityToken";
    string public symbol = "UTIL";
    uint8 public decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint256) private _bal;
    mapping(address => mapping(address => uint256)) private _allow;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address a) external view returns (uint256) { return _bal[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allow[o][s]; }

    function approve(address spender, uint256 value) external returns (bool) {
        _allow[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = _allow[from][msg.sender];
        require(a >= value, "ERC20: allowance");
        unchecked { _allow[from][msg.sender] = a - value; }
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external onlyOwner {
        require(to != address(0), "ERC20: zero addr");
        totalSupply += value;
        _bal[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burn(address from, uint256 value) external onlyOwner {
        require(_bal[from] >= value, "ERC20: balance");
        unchecked { _bal[from] -= value; }
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "ERC20: zero addr");
        require(_bal[from] >= value, "ERC20: balance");
        unchecked { _bal[from] -= value; _bal[to] += value; }
        emit Transfer(from, to, value);
    }
}

/**
 * GovernanceToken：与 UtilityToken 相同的 ERC20-like 实现，但增加 minter 角色。
 * - owner 永远可以 mint
 * - 被 setMinter 授权的合约/地址也可以 mint
 */
contract GovernanceToken is Ownable {
    string public name = "GovernanceToken";
    string public symbol = "GOV";
    uint8 public decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint256) private _bal;
    mapping(address => mapping(address => uint256)) private _allow;

    mapping(address => bool) public minters;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterSet(address indexed minter, bool allowed);

    modifier onlyMinter() {
        require(msg.sender == owner || minters[msg.sender], "GOV: not minter");
        _;
    }

    function setMinter(address m, bool allowed) external onlyOwner {
        minters[m] = allowed;
        emit MinterSet(m, allowed);
    }

    function balanceOf(address a) external view returns (uint256) { return _bal[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allow[o][s]; }

    function approve(address spender, uint256 value) external returns (bool) {
        _allow[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = _allow[from][msg.sender];
        require(a >= value, "GOV: allowance");
        unchecked { _allow[from][msg.sender] = a - value; }
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external onlyMinter {
        require(to != address(0), "GOV: zero addr");
        totalSupply += value;
        _bal[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burn(address from, uint256 value) external onlyOwner {
        require(_bal[from] >= value, "GOV: balance");
        unchecked { _bal[from] -= value; }
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "GOV: zero addr");
        require(_bal[from] >= value, "GOV: balance");
        unchecked { _bal[from] -= value; _bal[to] += value; }
        emit Transfer(from, to, value);
    }
}

/* ---------------------------- Reputation Manager -------------------------- */
contract ReputationManager is Ownable {
    mapping(address => int256) private _rep;
    mapping(address => bool) public authorizedUpdaters;

    event AuthorizedUpdaterSet(address indexed updater, bool allowed);
    event ReputationUpdated(address indexed user, int256 delta, int256 newValue);

    modifier onlyUpdater() {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner, "REP: not updater");
        _;
    }

    function setAuthorizedUpdater(address updater, bool allowed) external onlyOwner {
        authorizedUpdaters[updater] = allowed;
        emit AuthorizedUpdaterSet(updater, allowed);
    }

    function getReputation(address user) external view returns (int256) {
        return _rep[user];
    }

    function addReputation(address user, int256 delta) external onlyUpdater {
        _rep[user] += delta;
        emit ReputationUpdated(user, delta, _rep[user]);
    }
}

/* ----------------------------- TaskManager API ---------------------------- */
interface ITaskManager {
    function finalizeDispute(uint256 taskId, bool clientWins) external;
    function getTaskParties(uint256 taskId) external view returns (address client, address expert);
}

/* ------------------------- Arbitration / Dispute -------------------------- */
contract ArbitrationContract is Ownable {
    ReputationManager public reputation;
    address public taskManager;
    mapping(address => bool) public arbitrators;

    event TaskManagerSet(address indexed taskManager);
    event ArbitratorSet(address indexed arbitrator, bool allowed);
    event DisputeResolved(uint256 indexed taskId, bool clientWins, address indexed resolver);

    constructor(address reputationManager) {
        require(reputationManager != address(0), "ARB: zero addr");
        reputation = ReputationManager(reputationManager);
    }

    function setTaskManager(address tm) external onlyOwner {
        require(tm != address(0), "ARB: zero addr");
        taskManager = tm;
        emit TaskManagerSet(tm);
    }

    function setArbitrator(address a, bool allowed) external onlyOwner {
        arbitrators[a] = allowed;
        emit ArbitratorSet(a, allowed);
    }

    modifier onlyArbitrator() {
        require(arbitrators[msg.sender] || msg.sender == owner, "ARB: not arbitrator");
        _;
    }

    function resolveDispute(uint256 taskId, bool clientWins) external onlyArbitrator {
        require(taskManager != address(0), "ARB: taskManager unset");

        ITaskManager(taskManager).finalizeDispute(taskId, clientWins);

        (address client, address expert) = ITaskManager(taskManager).getTaskParties(taskId);
        if (client != address(0) && expert != address(0)) {
            if (clientWins) {
                reputation.addReputation(client, 10);
                reputation.addReputation(expert, -10);
            } else {
                reputation.addReputation(expert, 10);
                reputation.addReputation(client, -10);
            }
        }

        emit DisputeResolved(taskId, clientWins, msg.sender);
    }
}

/* --------------------------- Task Posting / Escrow ------------------------ */
contract TaskManager is Ownable {
    enum Status { Open, Taken, Submitted, Approved, Disputed, Resolved, Cancelled }

    struct Task {
        address client;
        address expert;
        string  description;
        uint256 price;
        uint256 deposit;
        Status  status;
        string  deliverableURI;
        uint64  createdAt;
        uint64  updatedAt;
    }

    UtilityToken public utilityToken;
    GovernanceToken public governanceToken;
    ReputationManager public reputation;
    address public arbitration;
    address public platformTreasury;

    uint16 public platformFeeBps = 1000; // 10%
    uint16 public disputeFeeBps  = 300;  // 3%
    uint256 public govRewardPerTask = 10e18;

    uint256 public nextTaskId;
    mapping(uint256 => Task) public tasks;

    event PlatformParamsUpdated(uint16 platformFeeBps, uint16 disputeFeeBps, uint256 govRewardPerTask);
    event TaskPosted(uint256 indexed taskId, address indexed client, uint256 price, uint256 deposit);
    event TaskAccepted(uint256 indexed taskId, address indexed expert);
    event TaskSubmitted(uint256 indexed taskId, string deliverableURI);
    event TaskApproved(uint256 indexed taskId);
    event TaskDisputed(uint256 indexed taskId);
    event TaskResolved(uint256 indexed taskId, bool clientWins);
    event TaskCancelled(uint256 indexed taskId);

    modifier onlyClient(uint256 taskId) {
        require(tasks[taskId].client == msg.sender, "TASK: not client");
        _;
    }

    modifier onlyArbitration() {
        require(msg.sender == arbitration, "TASK: not arbitration");
        _;
    }

    constructor(
        address _utilityToken,
        address _governanceToken,
        address _reputationManager,
        address _arbitration,
        address _platformTreasury
    ) {
        require(_utilityToken != address(0) && _governanceToken != address(0), "TASK: zero addr");
        require(_reputationManager != address(0) && _arbitration != address(0), "TASK: zero addr");
        require(_platformTreasury != address(0), "TASK: zero addr");

        utilityToken = UtilityToken(_utilityToken);
        governanceToken = GovernanceToken(_governanceToken);
        reputation = ReputationManager(_reputationManager);
        arbitration = _arbitration;
        platformTreasury = _platformTreasury;
    }

    function setPlatformParams(uint16 _platformFeeBps, uint16 _disputeFeeBps, uint256 _govRewardPerTask) external onlyOwner {
        require(_platformFeeBps <= 2000, "TASK: fee too high");
        require(_disputeFeeBps <= 1000, "TASK: dispute fee too high");
        platformFeeBps = _platformFeeBps;
        disputeFeeBps = _disputeFeeBps;
        govRewardPerTask = _govRewardPerTask;
        emit PlatformParamsUpdated(_platformFeeBps, _disputeFeeBps, _govRewardPerTask);
    }

    function postTask(string calldata description, uint256 price, uint256 deposit) external returns (uint256 taskId) {
        require(price > 0, "TASK: price=0");
        uint256 escrow = price + deposit;
        require(utilityToken.transferFrom(msg.sender, address(this), escrow), "TASK: transferFrom failed");

        taskId = nextTaskId++;
        tasks[taskId] = Task({
            client: msg.sender,
            expert: address(0),
            description: description,
            price: price,
            deposit: deposit,
            status: Status.Open,
            deliverableURI: "",
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        emit TaskPosted(taskId, msg.sender, price, deposit);
    }

    function acceptTask(uint256 taskId) external {
        Task storage t = tasks[taskId];
        require(t.status == Status.Open, "TASK: not open");
        require(t.client != address(0), "TASK: no task");
        t.expert = msg.sender;
        t.status = Status.Taken;
        t.updatedAt = uint64(block.timestamp);
        emit TaskAccepted(taskId, msg.sender);
    }

    function submitTask(uint256 taskId, string calldata deliverableURI) external {
        Task storage t = tasks[taskId];
        require(t.status == Status.Taken, "TASK: not taken");
        require(t.expert == msg.sender, "TASK: not expert");
        t.deliverableURI = deliverableURI;
        t.status = Status.Submitted;
        t.updatedAt = uint64(block.timestamp);
        emit TaskSubmitted(taskId, deliverableURI);
    }

    function approveTask(uint256 taskId) external onlyClient(taskId) {
        Task storage t = tasks[taskId];
        require(t.status == Status.Submitted, "TASK: not submitted");

        uint256 fee = (t.price * platformFeeBps) / 10_000;
        uint256 toExpert = t.price - fee;

        require(utilityToken.transfer(t.expert, toExpert), "TASK: pay expert failed");
        if (fee > 0) require(utilityToken.transfer(platformTreasury, fee), "TASK: pay fee failed");
        if (t.deposit > 0) require(utilityToken.transfer(t.client, t.deposit), "TASK: refund deposit failed");

        t.status = Status.Approved;
        t.updatedAt = uint64(block.timestamp);

        // Requires TaskManager authorized in ReputationManager
        reputation.addReputation(t.expert, 5);
        reputation.addReputation(t.client, 1);

        // Requires TaskManager set as minter in GovernanceToken
        if (govRewardPerTask > 0) {
            governanceToken.mint(t.expert, govRewardPerTask);
            governanceToken.mint(t.client, govRewardPerTask / 2);
        }

        emit TaskApproved(taskId);
    }

    function raiseDispute(uint256 taskId) external {
        Task storage t = tasks[taskId];
        require(t.status == Status.Submitted, "TASK: not eligible");
        require(msg.sender == t.client || msg.sender == t.expert, "TASK: not party");

        t.status = Status.Disputed;
        t.updatedAt = uint64(block.timestamp);
        emit TaskDisputed(taskId);
    }

    function finalizeDispute(uint256 taskId, bool clientWins) external onlyArbitration {
        Task storage t = tasks[taskId];
        require(t.status == Status.Disputed, "TASK: not disputed");

        uint256 disputeFee = (t.price * disputeFeeBps) / 10_000;

        if (clientWins) {
            uint256 refund = t.price + t.deposit;
            if (disputeFee > 0 && disputeFee <= refund) {
                refund -= disputeFee;
                require(utilityToken.transfer(platformTreasury, disputeFee), "TASK: dispute fee failed");
            }
            require(utilityToken.transfer(t.client, refund), "TASK: refund failed");
        } else {
            uint256 toExpert = t.price;
            if (disputeFee > 0 && disputeFee <= toExpert) {
                toExpert -= disputeFee;
                require(utilityToken.transfer(platformTreasury, disputeFee), "TASK: dispute fee failed");
            }
            require(utilityToken.transfer(t.expert, toExpert), "TASK: pay expert failed");
            if (t.deposit > 0) require(utilityToken.transfer(t.client, t.deposit), "TASK: refund deposit failed");
        }

        t.status = Status.Resolved;
        t.updatedAt = uint64(block.timestamp);
        emit TaskResolved(taskId, clientWins);
    }

    function cancelOpenTask(uint256 taskId) external onlyClient(taskId) {
        Task storage t = tasks[taskId];
        require(t.status == Status.Open, "TASK: not open");
        uint256 refund = t.price + t.deposit;
        require(utilityToken.transfer(t.client, refund), "TASK: refund failed");
        t.status = Status.Cancelled;
        t.updatedAt = uint64(block.timestamp);
        emit TaskCancelled(taskId);
    }

    function getTaskParties(uint256 taskId) external view returns (address client, address expert) {
        Task storage t = tasks[taskId];
        return (t.client, t.expert);
    }
}

/* --------------------------- Minimal ERC721-like -------------------------- */
contract KnowledgeNFT is Ownable {
    struct KnowledgeAsset {
        string  ipfsCID;
        bytes32 vectorHash;
        uint256 price;
        bool    isActive;
        uint64  createdAt;
        uint256 totalSales;
        uint256 revenue;
    }

    UtilityToken public utilityToken;

    address public platformAddress;
    address public daoAddress;
    uint16  public platformFeeBps = 2000; // 20%
    uint16  public daoFeeBps = 0;

    string public name = "KnowledgeNFT";
    string public symbol = "KNOW";

    uint256 public nextTokenId;

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(address => mapping(uint256 => bool)) public accessRights;
    mapping(uint256 => KnowledgeAsset) public assets;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event KnowledgeNFTMinted(uint256 indexed tokenId, address indexed owner, string ipfsCID, bytes32 vectorHash, uint256 price);
    event AccessPurchased(uint256 indexed tokenId, address indexed buyer, uint256 paid, uint256 platformFee, uint256 daoFee, uint256 ownerFee);
    event AssetPriceUpdated(uint256 indexed tokenId, uint256 newPrice);
    event AssetToggled(uint256 indexed tokenId, bool isActive);
    event FeeParamsUpdated(uint16 platformFeeBps, uint16 daoFeeBps, address platformAddress, address daoAddress);

    constructor(address _utilityToken, address _platform, address _dao) {
        require(_utilityToken != address(0), "NFT: zero token");
        require(_platform != address(0), "NFT: zero platform");
        utilityToken = UtilityToken(_utilityToken);
        platformAddress = _platform;
        daoAddress = _dao;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _ownerOf[tokenId];
        require(o != address(0), "ERC721: nonexistent");
        return o;
    }

    function balanceOf(address owner_) external view returns (uint256) {
        require(owner_ != address(0), "ERC721: zero addr");
        return _balanceOf[owner_];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_ownerOf[tokenId] != address(0), "ERC721: nonexistent");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner_, address operator) external view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "ERC721: not owner/approved");
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(to != address(0), "ERC721: zero addr");
        address o = ownerOf(tokenId);
        require(o == from, "ERC721: from != owner");

        bool ok = (msg.sender == o ||
                   _tokenApprovals[tokenId] == msg.sender ||
                   _operatorApprovals[o][msg.sender]);

        require(ok, "ERC721: not approved");

        _tokenApprovals[tokenId] = address(0);
        unchecked { _balanceOf[from] -= 1; _balanceOf[to] += 1; }
        _ownerOf[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function setFeeParams(uint16 _platformFeeBps, uint16 _daoFeeBps, address _platform, address _dao) external onlyOwner {
        require(_platformFeeBps <= 3000, "NFT: platform fee too high");
        require(_daoFeeBps <= 2000, "NFT: dao fee too high");
        require(_platform != address(0), "NFT: zero platform");
        require(_platformFeeBps + _daoFeeBps <= 5000, "NFT: fee sum too high");
        platformFeeBps = _platformFeeBps;
        daoFeeBps = _daoFeeBps;
        platformAddress = _platform;
        daoAddress = _dao;
        emit FeeParamsUpdated(_platformFeeBps, _daoFeeBps, _platform, _dao);
    }

    function mintKnowledgeNFT(string calldata ipfsCID, bytes32 vectorHash, uint256 price) external returns (uint256 tokenId) {
        require(bytes(ipfsCID).length > 0, "NFT: empty cid");
        tokenId = nextTokenId++;

        _ownerOf[tokenId] = msg.sender;
        _balanceOf[msg.sender] += 1;

        assets[tokenId] = KnowledgeAsset({
            ipfsCID: ipfsCID,
            vectorHash: vectorHash,
            price: price,
            isActive: true,
            createdAt: uint64(block.timestamp),
            totalSales: 0,
            revenue: 0
        });

        emit Transfer(address(0), msg.sender, tokenId);
        emit KnowledgeNFTMinted(tokenId, msg.sender, ipfsCID, vectorHash, price);
    }

    function setPrice(uint256 tokenId, uint256 newPrice) external {
        require(ownerOf(tokenId) == msg.sender, "NFT: not owner");
        assets[tokenId].price = newPrice;
        emit AssetPriceUpdated(tokenId, newPrice);
    }

    function toggleActive(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "NFT: not owner");
        assets[tokenId].isActive = !assets[tokenId].isActive;
        emit AssetToggled(tokenId, assets[tokenId].isActive);
    }

    function hasAccess(address user, uint256 tokenId) external view returns (bool) {
        return accessRights[user][tokenId] || ownerOf(tokenId) == user;
    }

    function purchaseAccess(uint256 tokenId) external {
        KnowledgeAsset storage a = assets[tokenId];
        require(a.isActive, "NFT: inactive");
        require(!accessRights[msg.sender][tokenId], "NFT: already purchased");
        require(a.price > 0, "NFT: price=0");

        require(utilityToken.transferFrom(msg.sender, address(this), a.price), "NFT: transferFrom failed");

        uint256 platformFee = (a.price * platformFeeBps) / 10_000;
        uint256 daoFee = (a.price * daoFeeBps) / 10_000;
        uint256 ownerFee = a.price - platformFee - daoFee;

        address assetOwner = ownerOf(tokenId);

        if (ownerFee > 0) require(utilityToken.transfer(assetOwner, ownerFee), "NFT: owner transfer failed");
        if (platformFee > 0) require(utilityToken.transfer(platformAddress, platformFee), "NFT: platform transfer failed");
        if (daoFee > 0 && daoAddress != address(0)) require(utilityToken.transfer(daoAddress, daoFee), "NFT: dao transfer failed");

        accessRights[msg.sender][tokenId] = true;

        a.totalSales += 1;
        a.revenue += a.price;

        emit AccessPurchased(tokenId, msg.sender, a.price, platformFee, daoFee, ownerFee);
    }
}
