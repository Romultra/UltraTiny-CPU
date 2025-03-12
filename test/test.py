import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

@cocotb.test()
async def test_tiny_cpu(dut):
    """Simple cocotb test for tt_tiny_cpu."""

    # Create a clock on dut.clk, 10ns period => 100 MHz
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Set initial signals
    dut.rst_n.value  = 0
    dut.ena.value    = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0

    # Wait a few cycles, then deassert reset
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Enable the CPU
    dut.ena.value = 1

    #-------------------------------------------------------------
    # LOAD A SMALL PROGRAM INTO THE CPU's MEMORY
    # Remember: if ui_in[7] = 1, the lower 4 bits of ui_in is
    # the memory address, and uio_in is the data to write.
    #
    # Example Program:
    #   0: 0x10      (LDA #imm)   => Next byte is immediate
    #   1: 0x0A      (the immediate: 10)
    #   2: 0x80      (LDB #imm)   => Next byte is immediate
    #   3: 0x03      (the immediate: 3)
    #   4: 0x20      (ADD B)      => ACC = ACC + B => 10 + 3 = 13
    #   5: 0x00      (NOP)
    # After this, the CPU’s ACC should be 13 decimal (0x0D).
    #-------------------------------------------------------------
    # Step 1: Enter program-load mode by setting ui_in[7]=1
    #   - the bottom 4 bits => address
    #   - uio_in => data
    #   - each clock cycle writes to mem
    # Step 2: Exit load mode by clearing ui_in[7], let CPU run
    #-------------------------------------------------------------

    # Enter load mode
    await load_memory(dut, address=0, data=0x10)  # LDA #imm
    await load_memory(dut, address=1, data=0x0A)  # imm = 10
    await load_memory(dut, address=2, data=0x80)  # LDB #imm
    await load_memory(dut, address=3, data=0x03)  # imm = 3
    await load_memory(dut, address=4, data=0x20)  # ADD B
    await load_memory(dut, address=5, data=0x00)  # NOP

    # End load mode: set ui_in[7] = 0
    dut.ui_in.value = 0b00000000
    await ClockCycles(dut.clk, 1)

    # Let the CPU run for a few cycles
    # It will fetch instructions from address 0..5
    await ClockCycles(dut.clk, 12)

    # Check that the Accumulator (uo_out) is 13 (0x0D)
    acc_val = dut.uo_out.value.integer
    dut._log.info(f"Accumulator = {acc_val} (expected 13)")
    assert acc_val == 13, f"FAIL: ACC was {acc_val}, expected 13"

    dut._log.info("SUCCESS: CPU produced the correct result after ADD B.")


async def load_memory(dut, address, data):
    """
    Helper coroutine to load one byte into the CPU memory at 'address'.
    The CPU uses ui_in[7]=1 to indicate 'load program mode', ui_in[3:0]
    as the address, and uio_in for the data.
    """
    # Bit 7 = 1 -> load mode
    # Bottom nibble = address
    # uio_in = data
    load_mode_value = 0x80 | (address & 0x0F)
    dut.ui_in.value = load_mode_value
    dut.uio_in.value = data

    # Wait one clock to store
    await ClockCycles(dut.clk, 1)
