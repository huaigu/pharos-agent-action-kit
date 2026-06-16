// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal ERC20 interface — inlined so this fixture compiles with bare
///      `forge build`, no OpenZeppelin dependency required.
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title MockVault
/// @notice A deliberately minimal ERC4626-style vault used ONLY as a demo target for
///         the `pharos-defi-play` skill. It lets an agent demonstrate a real
///         "approve -> deposit -> check shares -> withdraw" multi-step play on the
///         Pharos testnet without depending on any third-party protocol.
/// @dev    NOT production DeFi. Shares are minted 1:1 with deposited assets; there is
///         no yield, no fees, and no share-price math. Do not use with real value.
contract MockVault {
    /// @notice The ERC20 asset this vault accepts.
    IERC20 public immutable asset;

    /// @notice Share balance per depositor (1 share == 1 deposited asset unit).
    mapping(address => uint256) public balanceOf;

    /// @notice Total shares outstanding.
    uint256 public totalShares;

    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);

    constructor(address asset_) {
        require(asset_ != address(0), "MockVault: asset is zero address");
        asset = IERC20(asset_);
    }

    /// @notice Pull `assets` from the caller (requires a prior ERC20 approval to this
    ///         vault) and mint an equal number of shares.
    /// @dev    The `transferFrom` here is exactly what makes the approval step
    ///         mandatory — the whole point of the demo.
    function deposit(uint256 assets) external returns (uint256 shares) {
        require(assets > 0, "MockVault: deposit amount must be > 0");
        bool ok = asset.transferFrom(msg.sender, address(this), assets);
        require(ok, "MockVault: transferFrom failed (check allowance)");

        shares = assets; // 1:1
        balanceOf[msg.sender] += shares;
        totalShares += shares;

        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Burn `shares` from the caller and return an equal number of assets.
    function withdraw(uint256 shares) external returns (uint256 assets) {
        require(shares > 0, "MockVault: withdraw amount must be > 0");
        require(balanceOf[msg.sender] >= shares, "MockVault: insufficient shares");

        balanceOf[msg.sender] -= shares;
        totalShares -= shares;

        assets = shares; // 1:1
        bool ok = asset.transfer(msg.sender, assets);
        require(ok, "MockVault: asset transfer failed");

        emit Withdraw(msg.sender, assets, shares);
    }
}
