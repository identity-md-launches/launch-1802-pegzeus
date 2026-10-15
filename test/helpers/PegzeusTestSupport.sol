// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the cheatcodes these tests need; no external test dependency is required.
interface PegzeusVm {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

abstract contract PegzeusTestSupport {
    PegzeusVm internal constant vm = PegzeusVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Inclusive bounds, preserving in-range inputs and accepting the full uint256 domain.
    function bound(uint256 value, uint256 lower, uint256 upper) internal pure returns (uint256) {
        require(lower <= upper, "invalid test bounds");
        if (value >= lower && value <= upper) return value;
        // The full-width interval was already handled above, so its size cannot overflow here.
        return lower + value % (upper - lower + 1);
    }
}
