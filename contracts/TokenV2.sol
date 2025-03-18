// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITreasuryReceiver {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function treasuryReceive(uint256 amount) external;

    function treasuryReclaim(uint256 amount) external;
}

contract RegKeyToken is ERC20, Ownable {
    using ECDSA for bytes32;

    // Mappings for special addresses (Treasury, Liquidity pool, etc.)
    address public LIQUIDITY_POOL_ADDRESS;
    address public SALES_CONTRACT_ADDRESS;
    address public VESTING_POOL_CONTRACT;
    uint256 constant DUST = 0.01 ether; // Fixed amount to always leave as dust
    // Treasury addresses can store multiple addresses
    mapping(address => bool) public treasuryAddresses;

    address public masterHubAddress; // Address where isAdmin() is called.
    // masterHubAddress when hub is sales contract is the Token address
    struct TreasuryEntry {
        string label; // Smart contract purpose (“Sales”, “Vesting”, “LP_USDC”)
        uint256 totalTimesTransfered; // total successful transfers
        uint256 totalTimesReclaimed; // total successful reclaims
        uint256 totalTransferred; // Total tokens transferred to spoke
        uint256 totalReclaimed; // Total tokens reclaimed from spoke
        uint256[] failedReclaimAttemptAmounts; // Record of reclaim attempts exceeding total transferred
        uint256[] bouncedReclaimAmounts; // Record of reclaim attempts exceeding available amount
    }

    struct UserInfo {
        string registrarName;
        string registrarID;
        string countryCode;
        uint256 approvalLimit;
        uint8 permissionLevel;
        string reserved;
    }

    // Mappings for registrars, whitelisted contracts, directors, and admins
    mapping(address => bytes32) public registrarPubKeys;
    mapping(address => bool) public whitelistedSCPubAddresses;
    mapping(address => bool) public whiteListedDirectorAddresses;
    mapping(address => bool) public adminPubAddresses; // Admin addresses for managing lists
    mapping(address => uint256) public userTokenHoldings;
    mapping(address => TreasuryEntry) public treasury;
    mapping(address => string) public whitelistedUsers;
    address[] public smartContractAdmins;

    event TransferWithRegKey(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event UserWhitelisted(address indexed user, string registrationNote);
    event UserRemoved(address indexed user);
    event AdminUpdated(address indexed admin, bool status);

    // Constructor to initialize the ERC20 token
    constructor(string memory name, string memory symbol)
        Ownable(msg.sender)
        ERC20(name, symbol)
    {}

    modifier onlyExecutives() {
        require(adminPubAddresses[msg.sender], "Not an authorized executive");
        _;
    }

    // Function to add an admin address
    function addAdmin(address admin) external onlyOwner {
        adminPubAddresses[admin] = true;
    }

    // Function to remove an admin address
    function removeAdmin(address admin) external onlyOwner {
        adminPubAddresses[admin] = false;
    }

    // Function to add a user to the whitelist
    function addWhitelistedUser(address user, string memory registrationNote)
        external
        onlyExecutives
    {
        require(
            bytes(registrationNote).length > 0,
            "Invalid registration note"
        );
        whitelistedUsers[user] = registrationNote;
        emit UserWhitelisted(user, registrationNote);
    }

    // Function to remove a user from the whitelist
    function removeWhitelistedUser(address user) external onlyExecutives {
        require(bytes(whitelistedUsers[user]).length > 0, "User not found");
        delete whitelistedUsers[user];
        emit UserRemoved(user);
    }

    // Function to parse registration note into a structured format
    function parseUserInfo(address user) public view returns (UserInfo memory) {
        require(
            bytes(whitelistedUsers[user]).length > 0,
            "User not whitelisted"
        );

        string memory registrationNote = whitelistedUsers[user];
        string[] memory parts = split(registrationNote, "_");

        require(parts.length == 6, "Invalid registration note format");

        return
            UserInfo({
                registrarName: parts[0],
                registrarID: parts[1],
                countryCode: parts[2],
                approvalLimit: parseUint(parts[3]),
                permissionLevel: uint8(parseUint(parts[4])),
                reserved: parts[5]
            });
    }

    // Function to validate a transfer based on user's max allowed tokens
    function validateTransfer(address user, uint256 amount) internal view {
        UserInfo memory userInfo = parseUserInfo(user);

        require(userInfo.permissionLevel >= 1, "User lacks permission");

        uint256 newBalance = userTokenHoldings[user] + amount;
        require(
            newBalance <= userInfo.approvalLimit,
            "Exceeds allowed token limit"
        );
    }

    // Transfer function enforcing KYC compliance and max allocation check
    function transferWithKYC(address to, uint256 amount) external {
        validateTransfer(msg.sender, amount);
        _transfer(msg.sender, to, amount);
        userTokenHoldings[msg.sender] -= amount;
        userTokenHoldings[to] += amount;
    }

    // Helper function: Splits a string into an array by delimiter
    function split(string memory str, string memory delimiter)
        internal
        pure
        returns (string[] memory)
    {
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(str).length; i++) {
            if (bytes(str)[i] == bytes(delimiter)[0]) {
                count++;
            }
        }

        string[] memory parts = new string[](count);
        uint256 index = 0;
        bytes memory buffer;

        for (uint256 i = 0; i < bytes(str).length; i++) {
            if (bytes(str)[i] == bytes(delimiter)[0]) {
                parts[index] = string(buffer);
                buffer = "";
                index++;
            } else {
                buffer = abi.encodePacked(buffer, bytes(str)[i]);
            }
        }
        parts[index] = string(buffer);
        return parts;
    }

    // Helper function: Convert string to uint
    function parseUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid number");
            result = result * 10 + (uint8(b[i]) - 48);
        }
        return result;
    }

    // Add an address to the whitelist of smart contracts
    function addToWhitelist(address scAddress) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        whitelistedSCPubAddresses[scAddress] = true;
    }

    // Remove an address from the whitelist of smart contracts
    function removeFromWhitelist(address scAddress) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        whitelistedSCPubAddresses[scAddress] = false;
    }

    // Add an address to the whitelist of directors (still gated for KYC)
    function addWhiteListedDirector(address director) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        whiteListedDirectorAddresses[director] = true;
    }

    // Remove an address from the whitelist of directors (still gated for KYC)
    function removeWhiteListedDirector(address director) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        whiteListedDirectorAddresses[director] = false;
    }

    // Add a treasury address (for liquidity pools, sales, etc.)
    function addTreasuryAddress(address _treasury) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        treasuryAddresses[_treasury] = true;
    }

    // Remove a treasury address
    function removeTreasuryAddress(address _treasury) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        treasuryAddresses[_treasury] = false;
    }

    // Set the liquidity pool address (max 25% of total supply)
    function setLiquidityPoolAddress(address _address) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        LIQUIDITY_POOL_ADDRESS = _address;
    }

    // Set the sales contract address (max 25% of total supply)
    function setSalesContractAddress(address _address) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        SALES_CONTRACT_ADDRESS = _address;
    }

    // Set the vesting pool contract address (max 25% of total supply)
    function setVestingPoolContract(address _address) external {
        require(
            adminPubAddresses[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        VESTING_POOL_CONTRACT = _address;
    }

    // Function to add registrar with a signature for KYC validation
    function addRegistrar(bytes32 regKey, bytes memory signature) external {
        require(regKey != bytes32(0), "Invalid registration key");
        require(
            registrarPubKeys[msg.sender] == bytes32(0),
            "Registrar already exists"
        );

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender));
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address signer = ECDSA.recover(ethSignedMessageHash, signature);
        require(signer == msg.sender, "Invalid signature");

        registrarPubKeys[msg.sender] = regKey;
    }

    // Function to check if the sender's address is restricted or not
    function isRestricted(address sender, bytes32 regKey)
        public
        view
        returns (bool)
    {
        bytes32 storedKey = registrarPubKeys[sender];
        require(storedKey != bytes32(0), "Invalid registrar");

        return storedKey == regKey;
    }

    // Helper function to validate the transfer
    function validateTransfer(address sender, bytes32 regKey)
        internal
        view
        returns (bool)
    {
        // If the sender is whitelisted (either smart contract or director), allow the transfer
        if (
            whitelistedSCPubAddresses[sender] ||
            whiteListedDirectorAddresses[sender]
        ) {
            return true;
        }

        // If not whitelisted, the transfer needs to be validated using the registration key
        return isRestricted(sender, regKey);
    }

    // Transfer function that uses the registration key or allows transfer if the sender is whitelisted
    function transferWithRegKey(
        address to,
        uint256 amount,
        bytes32 regKey
    ) external {
        // Validate the transfer based on the sender's whitelist status or registration key
        require(validateTransfer(msg.sender, regKey), "Transfer not allowed");

        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, to, amount);

        emit TransferWithRegKey(msg.sender, to, amount);
    }

    function treasuryTransfer(
        address SCAddress,
        string memory label,
        uint256 amount
    ) external onlyExecutives {
        TreasuryEntry storage entry = treasury[SCAddress];

        if (bytes(entry.label).length != 0) {
            require(
                keccak256(bytes(entry.label)) == keccak256(bytes(label)),
                "Label mismatch for existing SC"
            );
        } else {
            entry.label = label;
        }

        // no longer have a maxAllowed since it would be editable anyway, it is moot.
        // keep this code comment here for reference anyway.
        // paradigm is not accounting control, but secure/flexible treasury functionality.
        // require(entry.maxAllowed >= entry.totalTransferred + amount, "Exceeds allowed
        //    limit");
        require(isContract(SCAddress), "Invalid contract");
        // change from interface to extending the abstract class ElasticTreasurySpoke
        require(
            ITreasuryReceiver(SCAddress).supportsInterface(
                type(ITreasuryReceiver).interfaceId
            ),
            "Contract does not implement required methods"
        );

        _transfer(address(this), SCAddress, amount);
        entry.totalTransferred += amount;

        ITreasuryReceiver(SCAddress).treasuryReceive(amount);

        // Add to smartContractAdmins array if not already included
        if (!_isSmartContractAdmin(SCAddress)) {
            smartContractAdmins.push(SCAddress);
        }
    }

    // Helper function to check if an address is a contract
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // Check if an address is already in the smartContractAdmins array
    function _isSmartContractAdmin(address SCAddress)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < smartContractAdmins.length; i++) {
            if (smartContractAdmins[i] == SCAddress) {
                return true;
            }
        }
        return false;
    }

    function treasuryReclaim(address SCAddress, uint256 amount)
        external
        onlyExecutives
    {
        uint256 availableToReclaim = treasury[SCAddress].totalTransferred -
            treasury[SCAddress].totalReclaimed;

        if (amount > treasury[SCAddress].totalTransferred) {
            treasury[SCAddress].failedReclaimAttemptAmounts.push(amount);
            revert("Reclaim exceeds total transferred");
        }

        if (amount > availableToReclaim) {
            treasury[SCAddress].bouncedReclaimAmounts.push(amount);
            amount = availableToReclaim - DUST;
        }

        ITreasuryReceiver(SCAddress).treasuryReclaim(amount);
        treasury[SCAddress].totalReclaimed += amount;

        _transfer(SCAddress, address(this), amount);
    }
}
