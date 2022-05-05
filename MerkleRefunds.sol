// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Merkle Refunds
/// @notice Set merkle roots, amounts, and make refunds :)
/// @author twitter.com/KfishNFT | github.com/KfishNFT
contract MerkleRefunds {
    /// @notice Used to keep track of addresses that have been refunded
    mapping(address => mapping(address => bool)) internal refunded;
    /// @notice Refund amounts
    mapping(address => uint256[]) internal refundAmounts;
    /// @notice Available merkle roots
    mapping(address => bytes32[]) internal merkleRoots;
    /// @notice Refunder balance
    mapping(address => uint256) internal refundBalance;


    /// @notice Emit event once ETH is refunded
    /// @param sender The address being refunded
    /// @param value The amount of ETH
    event Refunded(address indexed refunder, address indexed refunded, uint256 value);

    /// @notice Emit once merkle roots are added or updated
    /// @param refunder The address that is refunding
    /// @param merkleRoots_ The merkle roots
    /// @param refundAmounts_ Amounts corresponding to the merkle roots
    event MerkleRootsChanged(address indexed refunder, bytes32[] merkleRoots, uint256[] refundAmounts);

    /// @notice Emit once merkle roots are deleted
    /// @param refunder The address that is refunding
    /// @param merkleRoots_ The merkle roots
    /// @param refundAmounts_ Amounts corresponding to the merkle roots
    event MerkleRootsRemoved(address indexed refunder, bytes32[] merkleRoots, uint256[] refundAMounts);

    /// @notice Emit once balance is increased
    /// @param refunder The address that is refunding
    /// @param amount Amount added to balance
    event BalanceIncreased(address indexed refunder, uint256 amount);

    /// @notice Emit once balance is decreased
    /// @param refunder The address that is refunding
    /// @param amount Amount withdrawn from balance
    event BalanceDecreased(address indexed refunder, uint256 amount);

    /// @notice Emit once balance is withdrawn
    /// @param refunder The address that is refunding
    /// @param amount Amount withdrawn
    event BalanceWithdrawn(address indexed refunder, uint256 amount);

    /// @notice Sets the merkle root for refunds verification where the msg.sender is the refunder
    /// @param merkleRoots_ used to verify the refund list
    /// @param refundAmounts_ used to set the refund amounts
    function setMerkleRoots(
        bytes32[] merkleRoots_,
        uint256[] refundAmounts_,
    ) external payable {
        require(merkleRoots_.length == refundAmounts.length_, "Refunds: roots and amounts length not equal");
        merkleRoots[msg.sender] = merkleRoots_;
        refundAmounts[msg.sender] = refundAmounts_;
        if(msg.value > 0) {
            refundBalance[msg.sender] += msg.value;
        }

        emit MerkleRootsChanged(msg.sender, merkleRoots_, refundAmounts_);
    }

    /// @notice Increase balance of a refunder
    function increaseBalance() external payable {
        require(merkleRoots[msg.sender].length > 0, "Refunds: sender has no merkle roots");
        refundBalance[msg.sender] += msg.value;

        emit BalanceIncreased(msg.sender, msg.value);
    }

    /// @notice Decrease balance of a refunder
    function decreaseBalance(uint256 amount_) external {
        require(amount_ <= refundBalance[msg.sender], "Refunds: insufficient balance");
        refundBalance[msg.sender] -= amount_;
        (bool success, ) = payable(msg.sender).call{value: refundBalance[msg.sender]}("");
        require(success, "Refunds: withdrawal failed");

        emit BalanceDecreased(msg.sender, amount_);
    }

    /// @notice Remove merkle roots, amounts, and withdraw available balance for refunder
    function removeMerkleRoots() external {
        bytes32[] memory previousMerkleRoots = merkleRoots[msg.sender];
        uint256[] memory previousRefundAmounts = refundAmounts[msg.sender];
        uint256 previousBalance = refundBalance[msg.sender];
        delete merkleRoots[msg.sender];
        delete refundAmounts[msg.sender];
        if(refundBalance[msg.sender] > 0) {
            refundBalance[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: refundBalance[msg.sender]}("");
            require(success, "Refunds: withdrawal failed");
        }

        emit MerkleRootsRemoved(msg.sender, previousMerkleRoots, previousRefundAmounts, previousBalance);
    }

    /// @notice Issue refunds
    /// @dev requires a valid merkleRoot to function
    /// @param refunder_ The address who is refunding others
    /// @param merkleProof_ the proof sent by an refundable user
    function refund(address refunder_, bytes32[] calldata merkleProof_) external {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        for (uint256 i = 0; i < merkleRoots[refunder_].length; i++) {
            if(!refunded[refunder_][msg.sender] && MerkleProof.verify(merkleRoots[refunder_][i], merkleProof_, leaf)) {
                require(refundAmounts[refunder_][i] <= refundBalance[refunder_], "Refunds: refunder does not have enough balance");
                refunded[refunder_][msg.sender] = true;
                refundBalance[refunder_] -= refundAmounts[refunder_][i];
                payable(msg.sender).transfer(refundAmounts[refunder_][i]);
                emit Refunded(refunder_, msg.sender, refundAmounts[refunder_][i]);
                break;
            }
        }
        require(refunded[msg.sender], "Refunds: not refundable");
    }

    /// @notice Allow refunders to withdraw their balance
    function withdraw() external payable {
        require(refundBalance[msg.sender] > 0, "Refunds: nothing to withdraw");
        uint256 previousBalance = refundBalance[msg.sender];
        refundBalance[msg.sender] = 0;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = payable(msg.sender).call{value: refundBalance[msg.sender]}("");
        require(success, "Refunds: withdrawal failed");

        emit BalanceWithdrawn(msg.sender, previousBalance);
    }
}
