// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface ICoreToken {
    function registrationKeys(address user) external view returns (bytes32);
}

contract TokenSale is ReentrancyGuard, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    IERC20 public immutable usdcToken;
    IERC20 public immutable saleToken;
    ICoreToken public immutable coreToken;

    address public depositAddress;
    address public kycSigner;
    uint256 public tokenPriceUSDC = 4e16; // $0.04 per token in USDC
    uint256 public tokenPriceETH;
    uint256 public maxPurchaseLimit = 425_000 * 1e18;
    uint256 public totalTokensSold; // Tracks total tokens sold

    uint256 public saleStart;
    bool public isSaleActive;

    mapping(address => uint256) public userPurchased;

    event TokensPurchased(address indexed buyer, uint256 amount, bool inETH);
    event MaxPurchaseLimitUpdated(uint256 newLimit);
    event TokenPriceUpdated(uint256 newPriceETH, uint256 newPriceUSDC);
    event KycSignerUpdated(address newKycSigner);
    event DepositAddressUpdated(address newDepositAddress);
    event SaleStarted(uint256 startTimestamp);

    constructor(
        address _usdcToken,
        address _saleToken,
        address _depositAddress,
        address _kycSigner,
        uint256 _tokenPriceETH
    ) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        saleToken = IERC20(_saleToken);
        coreToken = ICoreToken(_saleToken);
        depositAddress = _depositAddress;
        kycSigner = _kycSigner;
        tokenPriceETH = _tokenPriceETH;

        saleStart = 0;
        isSaleActive = false;
    }

    function startSale(uint256 _startTimestamp) external onlyOwner {
        require(!isSaleActive, "Sale already active");
        require(_startTimestamp > block.timestamp, "Start must be future");
        saleStart = _startTimestamp;
        isSaleActive = true;

        emit SaleStarted(_startTimestamp);
    }

    function pauseSale() external onlyOwner {
        isSaleActive = false;
    }

    function setKycSigner(address _kycSigner) external onlyOwner {
        kycSigner = _kycSigner;
        emit KycSignerUpdated(_kycSigner);
    }

    function setDepositAddress(address _deposit) external onlyOwner {
        depositAddress = _deposit;
        emit DepositAddressUpdated(_deposit);
    }

    function buy(
        bytes32 regKey,
        address pubKey,
        uint256 amountIfUSDC,
        bytes memory signature
    ) external payable nonReentrant {
        require(isSaleActive, "Sale not active");
        require(block.timestamp >= saleStart, "Sale not started");

        require(pubKey == msg.sender, "Invalid buyer");
        require(isWhitelisted(msg.sender, regKey, signature), "Invalid KYC");

        uint256 tokenAmount;
        bool inETH = msg.value > 0;

        if (inETH) {
            require(tokenPriceETH > 0, "ETH price not set");
            tokenAmount = msg.value / tokenPriceETH;
            require(tokenAmount > 0, "Invalid ETH amount");
        } else {
            require(amountIfUSDC > 0, "No USDC amount specified");
            tokenAmount = (amountIfUSDC * 1e18) / tokenPriceUSDC;
            require(tokenAmount > 0, "Invalid USDC amount");
        }

        require(
            userPurchased[msg.sender] + tokenAmount <= maxPurchaseLimit,
            "Exceeds max purchase limit"
        );

        if (inETH) {
            (bool success, ) = depositAddress.call{value: msg.value}("");
            require(success, "ETH transfer failed");
        } else {
            usdcToken.safeTransferFrom(
                msg.sender,
                depositAddress,
                amountIfUSDC
            );
        }

        require(
            saleToken.balanceOf(address(this)) >= tokenAmount,
            "Not enough tokens in contract"
        );
        saleToken.safeTransfer(msg.sender, tokenAmount);

        userPurchased[msg.sender] += tokenAmount;
        totalTokensSold += tokenAmount; // Track total tokens sold
        emit TokensPurchased(msg.sender, tokenAmount, inETH);
    }

    function isWhitelisted(
        address user,
        bytes32 regKey,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 storedRegKey = coreToken.registrationKeys(user);

        if (storedRegKey != regKey || storedRegKey == bytes32(0)) {
            return false;
        }

        // Hash the regKey like in registerKey function
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", regKey)
        );

        // Recover the signer from the signature
        address recoveredSigner = recoverSigner(messageHash, signature);

        // Check if the recovered address is the kycSigner
        return recoveredSigner == kycSigner;
    }

    function test(
        address user,
        bytes32 regKey,
        bytes memory signature
    ) public view returns (address) {
        bytes32 storedRegKey = coreToken.registrationKeys(user);

        if (storedRegKey != regKey || storedRegKey == bytes32(0)) {
            return address(0);
        }

        // Hash the regKey like in registerKey function
        bytes32 messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", regKey)
        );

        // Recover the signer from the signature
        address recoveredSigner = recoverSigner(messageHash, signature);

        // Check if the recovered address is the kycSigner
        return recoveredSigner;
    }

    function getMessageHash(
        string memory message
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encodePacked(message))
                )
            );
    }

    function recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) public pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }

        return ecrecover(messageHash, v, r, s);
    }

    function setTokenPriceETH(uint256 newPrice) external onlyOwner {
        tokenPriceETH = newPrice;
        emit TokenPriceUpdated(newPrice, tokenPriceUSDC);
    }

    function setTokenPriceUSDC(uint256 newPrice) external onlyOwner {
        tokenPriceUSDC = newPrice;
        emit TokenPriceUpdated(tokenPriceETH, newPrice);
    }

    function updateMaxPurchaseLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Limit must be > 0");
        maxPurchaseLimit = newLimit;
        emit MaxPurchaseLimitUpdated(newLimit);
    }

    function emergencyWithdrawTokens(
        IERC20 token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        token.safeTransfer(to, amount);
    }
}
