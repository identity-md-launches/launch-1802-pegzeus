// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pegzeus} from "../src/Pegzeus.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

/// @dev Models deployment by a launch factory without any constructor configuration.
contract DeploymentProbe {
    function deploy() external returns (Pegzeus) {
        return new Pegzeus();
    }
}

contract PegzeusTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    Pegzeus private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pegzeus();
    }

    function testMetadataAndSupply() public view {
        require(keccak256(bytes(token.name())) == keccak256("Pegzeus"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("PEGZ"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.INITIAL_SUPPLY() == SUPPLY, "supply constant");
        require(token.totalSupply() == SUPPLY, "supply");
        require(token.balanceOf(address(this)) == SUPPLY, "deployer balance");
        require(token.balanceOf(ALICE) == 0, "unexpected allocation");
        require(token.allowance(address(this), SPENDER) == 0, "initial allowance");
    }

    function testConstructorEmitsMintEvent() public {
        // The new token address is not yet available, so check the event contents.
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        Pegzeus deployed = new Pegzeus();
        require(deployed.balanceOf(address(this)) == SUPPLY, "mint recipient");
    }

    function testFactoryReceivesEntireSupply() public {
        DeploymentProbe factory = new DeploymentProbe();
        Pegzeus deployed = factory.deploy();
        require(deployed.balanceOf(address(factory)) == SUPPLY, "factory allocation");
        require(deployed.balanceOf(address(this)) == 0, "caller allocation");
        require(deployed.totalSupply() == SUPPLY, "factory supply");
    }

    function testTransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        require(token.transfer(ALICE, 123 ether), "transfer return");
        require(token.balanceOf(ALICE) == 123 ether, "recipient amount");
        require(token.balanceOf(address(this)) == SUPPLY - 123 ether, "sender amount");
        require(token.totalSupply() == SUPPLY, "transfer supply");
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "zero balances");
    }

    function testSelfTransferPreservesBalance() public {
        require(token.transfer(address(this), SUPPLY), "self transfer");
        require(token.balanceOf(address(this)) == SUPPLY, "self balance");
        require(token.totalSupply() == SUPPLY, "self supply");
    }

    function testTransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        require(token.balanceOf(address(this)) == SUPPLY, "revert balance");
    }

    function testTransferExceedingBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        require(token.balanceOf(address(this)) == SUPPLY, "sender changed");
        require(token.balanceOf(ALICE) == 0, "recipient changed");
    }

    function testApproveReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        require(token.approve(SPENDER, 50 ether), "approve return");
        require(token.allowance(address(this), SPENDER) == 50 ether, "approve amount");
        require(token.approve(SPENDER, 7 ether), "replace");
        require(token.allowance(address(this), SPENDER) == 7 ether, "replace amount");
        require(token.approve(SPENDER, 0), "revoke");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(address(this)) == SUPPLY, "approval moved funds");
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function testTransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 4 ether), "transferFrom return");
        require(token.allowance(address(this), SPENDER) == 6 ether, "remaining allowance");
        require(token.balanceOf(ALICE) == 4 ether, "transferFrom delivered");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 6 ether), "spend remainder");
        require(token.allowance(address(this), SPENDER) == 0, "exhausted allowance");
    }

    function testInfiniteAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 1 ether), "infinite spend");
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "infinite allowance");
    }

    function testUnapprovedTransferFromRevertsEvenForDeployer() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        require(token.balanceOf(ALICE) == 10 ether, "holder balance");
    }

    function testTransferFromExceedingAllowanceReverts() public {
        token.approve(SPENDER, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 3, 4));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 4);
        require(token.allowance(address(this), SPENDER) == 3, "allowance changed");
        require(token.balanceOf(ALICE) == 0, "balance changed");
    }

    function testTransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        require(token.allowance(ALICE, SPENDER) == 10, "allowance rollback");
        require(token.balanceOf(BOB) == 0, "balance rollback");
    }

    function testTransferFromToZeroRollsBackAllowance() public {
        token.approve(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 1);
        require(token.allowance(address(this), SPENDER) == 1, "zero recipient rollback");
        require(token.totalSupply() == SUPPLY, "no burn");
    }

    function testZeroTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero delegated transfer");
        require(token.allowance(ALICE, SPENDER) == 0, "zero allowance");
    }

    function testTransferFromZeroSenderReverts() public {
        // Spending a zero allowance validates the approver before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function testNoMintOrPrivilegedControlFromDeployerOrStranger() public {
        token.transfer(ALICE, 100 ether);
        bytes[8] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("transferOwnership(address)", BOB)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            require(!success, "deployer privileged call");
            vm.prank(BOB);
            (success,) = address(token).call(calls[i]);
            require(!success, "stranger privileged call");
        }
        require(token.balanceOf(ALICE) == 100 ether, "holder changed");
        require(token.totalSupply() == SUPPLY, "supply changed");
        vm.prank(ALICE);
        require(token.transfer(BOB, 100 ether), "holder frozen");
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 rawAmount) public {
        if (recipient == address(0) || recipient == address(this)) return;
        uint256 amount = rawAmount % (SUPPLY + 1);
        require(token.transfer(recipient, amount), "fuzz transfer");
        require(token.balanceOf(recipient) == amount, "fuzz received");
        require(token.balanceOf(address(this)) == SUPPLY - amount, "fuzz sender");
        require(token.totalSupply() == SUPPLY, "fuzz supply");
    }

    function testFuzzDelegatedTransfer(uint256 rawAmount, uint256 rawAllowance) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        uint256 allowance = rawAllowance % (SUPPLY + 1);
        token.approve(SPENDER, allowance);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, amount)
            );
            vm.prank(SPENDER);
            token.transferFrom(address(this), ALICE, amount);
            require(token.allowance(address(this), SPENDER) == allowance, "fuzz failed allowance");
            require(token.balanceOf(ALICE) == 0, "fuzz failed balance");
        } else {
            vm.prank(SPENDER);
            require(token.transferFrom(address(this), ALICE, amount), "fuzz delegated");
            require(token.allowance(address(this), SPENDER) == allowance - amount, "fuzz allowance");
            require(token.balanceOf(ALICE) == amount, "fuzz delegated balance");
        }
        require(token.totalSupply() == SUPPLY, "fuzz delegated supply");
    }

    /// @dev Exercises repeated transfers and approvals, including self-transfers, across four holders.
    function testFuzzSequenceConservesBalances(bytes32 seed) public {
        address[4] memory holders = [address(this), ALICE, BOB, SPENDER];
        for (uint256 i; i < 40; ++i) {
            seed = keccak256(abi.encode(seed, i));
            address from = holders[uint256(seed) % 4];
            address to = holders[(uint256(seed) >> 8) % 4];
            uint256 amount = (uint256(seed) >> 16) % (token.balanceOf(from) + 1);
            if (i % 2 == 0) {
                vm.prank(from);
                require(token.transfer(to, amount), "sequence transfer");
            } else {
                vm.prank(from);
                require(token.approve(address(this), amount), "sequence approve");
                require(token.transferFrom(from, to, amount), "sequence delegated");
                require(token.allowance(from, address(this)) == 0, "sequence allowance");
            }
            uint256 sum;
            for (uint256 j; j < holders.length; ++j) {
                sum += token.balanceOf(holders[j]);
            }
            require(sum == SUPPLY && token.totalSupply() == SUPPLY, "sequence conservation");
        }
    }
}
