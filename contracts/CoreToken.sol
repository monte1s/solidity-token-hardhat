// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract CoreToken is ERC20, AccessControl {
    /// @notice Total supply of 850,000,000 tokens
    uint256 public constant TOTAL_SUPPLY = 850_000_000 * 10 ** 18;

    /// @notice Roles
    bytes32 public constant TREASURER = keccak256("TREASURER");

    /// @notice Array of Treasury addresses storing all tokens
    address[] public coreTreasuries;

    /// @notice Sale and Vesting contract addresses
    address public saleContract;
    address public vestingContract;

    /// @notice Tracks allocated amounts for Sale & Vesting
    uint256 public saleAllocation;
    uint256 public vestingAllocation;

    /// @notice Transfer restriction flag (true = restricted, false = unrestricted)
    bool public transferRestricted = true;

    /// @notice Mapping for user registration keys
    mapping(address => bytes32) public registrationKeys;

    /// @notice Events for tracking transactions
    event TransferToSale(address indexed to, uint256 amount);
    event TransferToVest(address indexed to, uint256 amount);
    event WithdrawUnsoldTokens(address indexed to, uint256 amount);
    event TransferRestrictionRemoved();
    event RegistrationKeySet(address indexed user, bytes32 key);
    event TreasurerUpdated(address indexed user, bool granted);
    event TokensBurned(address indexed from, uint256 amount);
    event TreasuryAddressAdded(address indexed treasury);
    event TreasuryAddressRemoved(address indexed treasury);

    constructor(
        address _admin,
        address _coreTreasury
    ) ERC20("CoreToken", "CORE") {
        require(_admin != address(0), "Invalid admin address");
        require(_coreTreasury != address(0), "Invalid treasury address");

        coreTreasuries.push(_coreTreasury); // Add the initial treasury address

        // Mint all tokens to the first coreTreasury address
        _mint(_coreTreasury, TOTAL_SUPPLY);

        // Assign roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin); // Set the given admin
        _grantRole(TREASURER, _admin); // Admin is also a treasurer by default
    }

    /// @notice Set the Sale contract addresses (Admin only)
    function setSaleContracts(
        address _saleContract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_saleContract != address(0), "Invalid addresses");
        saleContract = _saleContract;
    }

    /// @notice Set the Vesting contract addresses (Admin only)
    function setVestContracts(
        address _vestingContract
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vestingContract != address(0), "Invalid addresses");
        vestingContract = _vestingContract;
    }

    /// @notice Assign or remove TREASURER_ROLE (Only Admin)
    function setTreasurer(
        address user,
        bool grant
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(user != address(0), "Invalid address");
        if (grant) {
            _grantRole(TREASURER, user);
        } else {
            _revokeRole(TREASURER, user);
        }
        emit TreasurerUpdated(user, grant);
    }

    /// @notice Transfer tokens to the Sale contract (Only Treasurer)
    function transferToSale(
        uint256 amount,
        address _coreTreasury
    ) external onlyRole(TREASURER) {
        require(isTreasury(_coreTreasury), "Invalid treasury address");
        require(saleContract != address(0), "Sale contract not set");
        _transfer(_coreTreasury, saleContract, amount);
        saleAllocation += amount;
        emit TransferToSale(saleContract, amount);
    }

    /// @notice Transfer tokens to the Vesting contract (Only Treasurer)
    function transferToVest(
        uint256 amount,
        address _coreTreasury
    ) external onlyRole(TREASURER) {
        require(isTreasury(_coreTreasury), "Invalid treasury address");
        require(vestingContract != address(0), "Vesting contract not set");
        _transfer(_coreTreasury, vestingContract, amount);
        vestingAllocation += amount;
        emit TransferToVest(vestingContract, amount);
    }

    /// @notice Withdraw unsold tokens back to CORE_TREASURIES (Only Admin)
    function withdrawUnsoldTokens(
        uint256 amount,
        address _coreTreasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isTreasury(_coreTreasury), "Invalid treasury address");
        require(saleContract != address(0), "Sale contract not set");
        require(
            balanceOf(saleContract) >= amount,
            "Insufficient balance in Sale contract"
        );

        _transfer(saleContract, _coreTreasury, amount);
        saleAllocation -= amount;
        emit WithdrawUnsoldTokens(_coreTreasury, amount);
    }

    /// @notice Modifier to check registration key before transfers
    modifier checkTransferRestrictions(address sender) {
        if (transferRestricted) {
            if (
                sender != coreTreasuries[0] &&
                sender != saleContract &&
                sender != vestingContract &&
                !hasRole(DEFAULT_ADMIN_ROLE, sender)
            ) {
                require(
                    registrationKeys[sender] != bytes32(0),
                    "User not registered"
                );
            }
        }
        _;
    }

    /// @notice Override ERC20 transfer function
    function transfer(
        address to,
        uint256 amount
    ) public override checkTransferRestrictions(msg.sender) returns (bool) {
        return super.transfer(to, amount);
    }

    /// @notice Override ERC20 transferFrom function
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override checkTransferRestrictions(from) returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    function recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) public pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Extract r, s, v from the signature
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }

        // Recover signer address
        return ecrecover(messageHash, v, r, s);
    }

    /// @notice Allow users to register their transfer key
    function registerKey(bytes32 key, bytes memory signature) external {
        require(
            registrationKeys[msg.sender] == bytes32(0),
            "Already registered"
        );

        // Hash the key
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", key)
        );

        // Recover signer
        address signer = recoverSigner(messageHash, signature);

        require(signer == msg.sender, "Invalid signature");

        registrationKeys[msg.sender] = key;
        emit RegistrationKeySet(msg.sender, key);
    }

    /// @notice Remove transfer restrictions (Only Admin)
    function removeTransferRestriction() external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestricted = false;
        emit TransferRestrictionRemoved();
    }

    /// @notice Add a new treasury address (Only Admin)
    function addTreasuryAddress(
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid treasury address");
        coreTreasuries.push(_treasury);
        emit TreasuryAddressAdded(_treasury);
    }

    /// @notice Remove a treasury address (Only Admin)
    function removeTreasuryAddress(
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid treasury address");

        uint256 index = findTreasuryIndex(_treasury);
        coreTreasuries[index] = coreTreasuries[coreTreasuries.length - 1];
        coreTreasuries.pop();

        emit TreasuryAddressRemoved(_treasury);
    }

    /// @notice Find the index of a treasury address
    function findTreasuryIndex(
        address _treasury
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < coreTreasuries.length; i++) {
            if (coreTreasuries[i] == _treasury) {
                return i;
            }
        }
        revert("Treasury address not found");
    }

    /// @notice Burn tokens from a specific treasury address (Only Admin)
    function burn(
        address _treasury,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isTreasury(_treasury), "Invalid treasury address");
        _burn(_treasury, amount);
        emit TokensBurned(_treasury, amount);
    }

    /// @notice Check if an address is a treasury
    function isTreasury(address _treasury) public view returns (bool) {
        for (uint256 i = 0; i < coreTreasuries.length; i++) {
            if (coreTreasuries[i] == _treasury) {
                return true;
            }
        }
        return false;
    }
}
