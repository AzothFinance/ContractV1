// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol)
/// @dev The original library has been modified to make it suitable for different decimals
library FixedPointMathLib {
    /// @dev The operation failed, due to an multiplication overflow.
    error MulWadFailed();

    /// @dev The operation failed, either due to a multiplication overflow, or a division by a zero.
    error DivWadFailed();

    /// @dev The scalar of ETH and most ERC20s.
    // uint256 internal constant WAD = 1e18;   // <==== remove

    /// @dev Equivalent to `(x * y) / WAD` rounded down.
    function mulWad(uint256 x, uint256 y, uint8 decimals) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let divisor := exp(10, decimals)  // <=== ADD
            // Equivalent to `require(y == 0 || x <= type(uint256).max / y)`.
            if gt(x, div(not(0), y)) {
                if y {
                    mstore(0x00, 0xbac65e5b) // `MulWadFailed()`.
                    revert(0x1c, 0x04)
                }
            }
            // z := div(mul(x, y), WAD)
            z := div(mul(x, y), divisor)
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded up.
    function mulWadUp(uint256 x, uint256 y, uint8 decimals) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let divisor := exp(10, decimals)  // <==== ADD
            z := mul(x, y)
            // Equivalent to `require(y == 0 || x <= type(uint256).max / y)`.
            if iszero(eq(div(z, y), x)) {
                if y {
                    mstore(0x00, 0xbac65e5b) // `MulWadFailed()`.
                    revert(0x1c, 0x04)
                }
            }
            // z := add(iszero(iszero(mod(z, WAD))), div(z, WAD))
            z := add(iszero(iszero(mod(z, divisor))), div(z, divisor))
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded down.
    function divWad(uint256 x, uint256 y, uint8 decimals) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let divisor := exp(10, decimals)  // <==== ADD
            // Equivalent to `require(y != 0 && x <= type(uint256).max / WAD)`.
            // if iszero(mul(y, lt(x, add(1, div(not(0), WAD))))) {
            if iszero(mul(y, lt(x, add(1, div(not(0), divisor))))) {
                mstore(0x00, 0x7c5f487d) // `DivWadFailed()`.
                revert(0x1c, 0x04)
            }
            // z := div(mul(x, WAD), y)
            z := div(mul(x, divisor), y)
        }
    }

    /// @dev Equivalent to `(x * WAD) / y` rounded up.
    function divWadUp(uint256 x, uint256 y, uint8 decimals) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            let divisor := exp(10, decimals)  // <==== ADD
            // Equivalent to `require(y != 0 && x <= type(uint256).max / WAD)`.
            // if iszero(mul(y, lt(x, add(1, div(not(0), WAD))))) {
            if iszero(mul(y, lt(x, add(1, div(not(0), divisor))))) {
                mstore(0x00, 0x7c5f487d) // `DivWadFailed()`.
                revert(0x1c, 0x04)
            }
            // z := add(iszero(iszero(mod(mul(x, WAD), y))), div(mul(x, WAD), y))
            z := add(iszero(iszero(mod(mul(x, divisor), y))), div(mul(x, divisor), y))
        }
    }

    /// @dev Returns `ceil(x * y / d)`.
    /// Reverts if `x * y` overflows, or `d` is zero.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(x, y)
            // Equivalent to `require(d != 0 && (y == 0 || x <= type(uint256).max / y))`.
            if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                mstore(0x00, 0xad251c27) // `MulDivFailed()`.
                revert(0x1c, 0x04)
            }
            z := add(iszero(iszero(mod(z, d))), div(z, d))
        }
    }
}