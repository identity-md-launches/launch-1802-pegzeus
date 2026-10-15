// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pegzeus} from "../../src/Pegzeus.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PegzeusTestSupport} from "../helpers/PegzeusTestSupport.sol";

/// @dev Closed accounting universe: four senders plus the token as a passive recipient.
/// The deployer is actor 0. No actor receives synthetic balances through storage cheatcodes.
contract PegzeusHandler is PegzeusTestSupport {
    Pegzeus public immutable token;
    address[4] public actors;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public debits;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public successfulTransfers;
    uint256 public successfulDelegatedTransfers;
    uint256 public successfulApprovals;
    uint256 public rejectedCalls;

    constructor() {
        token = new Pegzeus();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        credits[address(this)] = SUPPLY;
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], SUPPLY / 4), "initial distribution failed");
            _recordTransfer(address(this), actors[i], SUPPLY / 4);
        }
    }

    function expectedBalance(address account) public view returns (uint256) {
        return credits[account] - debits[account];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount, bool fullBalance) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = fullBalance ? balance : bound(rawAmount, 0, balance);
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        _recordTransfer(from, to, amount);
        ++successfulTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount;
        if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(rawAmount, 0, SUPPLY);
        else if (mode % 4 == 3) amount = rawAmount;
        // Mode 0 revokes, including allowances which were previously infinite.
        vm.prank(owner);
        require(token.approve(spender, amount), "approve returned false");
        expectedAllowance[owner][spender] = amount;
        ++successfulApprovals;
    }

    /// @dev Uses existing approvals, so spending, replacement and revocation interact across calls.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool fullAvailable)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance(owner);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < limit) limit = allowed;
        uint256 amount = fullAvailable ? limit : bound(rawAmount, 0, limit);
        _attemptTransferFrom(owner, spender, _recipient(toSeed), amount);
    }

    /// @dev Deliberately exceeds balances, including one-over and uint256-max cases.
    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (_recipient(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    /// @dev Invalid attempts are caught and checked, never discarded as handler reverts.
    function attemptTransferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, uint8 mode)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = rawAmount;
        if (mode % 3 == 0) amount = expectedBalance(owner) + 1;
        if (mode % 3 == 1) {
            uint256 allowed = expectedAllowance[owner][spender];
            amount = allowed == type(uint256).max ? allowed : allowed + 1;
        }
        _attemptTransferFrom(owner, spender, _recipient(toSeed), amount);
    }

    function invalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance(owner);
        if (delegated && expectedAllowance[owner][spender] < limit) limit = expectedAllowance[owner][spender];
        uint256 amount = bound(rawAmount, 0, limit);
        bytes memory callData = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _expectFailure(
            delegated ? spender : owner,
            callData,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function invalidSpender(uint256 ownerSeed, uint256 amount) external {
        _expectFailure(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    /// @dev Mix administrative probes with ordinary holder activity, from deployer and strangers.
    function forbiddenControl(uint256 callerSeed, uint256 holderSeed, uint256 amount, uint8 kind) external {
        address holder = _actor(holderSeed);
        bytes memory callData;
        uint256 choice = kind % 7;
        if (choice == 0) callData = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (choice == 1) callData = abi.encodeWithSignature("burn(uint256)", amount);
        else if (choice == 2) callData = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (choice == 3) callData = abi.encodeWithSignature("pause()");
        else if (choice == 4) callData = abi.encodeWithSignature("blacklist(address)", holder);
        else if (choice == 5) callData = abi.encodeWithSignature("initialize(address)", holder);
        else callData = abi.encodeWithSignature("transferOwnership(address)", holder);
        vm.prank(_actor(callerSeed));
        (bool success,) = address(token).call(callData);
        require(!success, "unexpected privileged entry point");
        ++rejectedCalls;
    }

    function _attemptTransferFrom(address owner, address spender, address to, uint256 amount) private {
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance(owner);
        bytes memory callData = abi.encodeCall(token.transferFrom, (owner, to, amount));
        if (allowed < amount) {
            _expectFailure(
                spender,
                callData,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        } else if (balance < amount) {
            _expectFailure(
                spender,
                callData,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
        } else {
            vm.prank(spender);
            require(token.transferFrom(owner, to, amount), "transferFrom returned false");
            _recordTransfer(owner, to, amount);
            if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
            ++successfulDelegatedTransfers;
        }
    }

    function _expectFailure(address caller, bytes memory callData, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(callData);
        require(!success, "invalid operation succeeded");
        require(keccak256(result) == keccak256(expectedError), "unexpected revert reason");
        ++rejectedCalls;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        // Cumulative requested flows are independent of the token's reported balances.
        debits[from] += amount;
        credits[to] += amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = seed % (actors.length + 1);
        return index == actors.length ? address(token) : actors[index];
    }
}
