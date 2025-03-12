`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // ----------------------------------------------------------------------
  // Generate Waveform Dump for Debug (useful for GTKWave)
  // ----------------------------------------------------------------------
  initial begin
      $dumpfile("tb.vcd");
      $dumpvars(0, tb);
      #1;
  end

  // ----------------------------------------------------------------------
  // Testbench signals
  // ----------------------------------------------------------------------
  reg  clk;
  reg  rst_n;
  reg  ena;
  reg  [7:0]  ui_in;    // Dedicated inputs to the CPU
  wire [7:0]  uo_out;   // Dedicated outputs from the CPU
  reg  [7:0]  uio_in;   // IO inputs to the CPU
  wire [7:0]  uio_out;  // IO outputs (unused in test)
  wire [7:0]  uio_oe;   // IO enable (unused in test)
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // ----------------------------------------------------------------------
  // Instantiate the CPU
  // Replace the module name with your top-level if different.
  // ----------------------------------------------------------------------
  // Replace tt_um_example with your module name:
  tt_um_ultra_tiny_cpu user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
    .VPWR(VPWR),
    .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

  // ----------------------------------------------------------------------
  // Clock Generation: 10ns period => 100 MHz
  // Adjust period to suit your design's assumed clock.
  // ----------------------------------------------------------------------
  initial begin
      clk = 0;
      forever #5 clk = ~clk;  // Toggles every 5 ns
  end

  // ----------------------------------------------------------------------
  // Test Process
  // ----------------------------------------------------------------------
  initial begin
      // Initial conditions
      rst_n  = 0;
      ena    = 0;
      ui_in  = 8'd0;  // All zero
      uio_in = 8'd0;

      // Wait some time before releasing reset
      #20;
      rst_n = 1;    // Deassert reset
      #20;

      // Enable the CPU
      ena = 1;  
      #10;

      // ------------------------------------------------------------------
      // LOAD MODE: ui_in[7] = 1 -> load instructions/data to memory
      // ------------------------------------------------------------------
      ui_in[7] = 1'b1;

      // Example: write a few bytes into memory:
      // mem[0] = 0x10 => LDA #imm
      // mem[1] = 0x42 => (the immediate value)
      // mem[2] = 0x70 => NOT ACC
      // mem[3] = 0x00 => NOP
      // The CPU should end with ACC = ~0x42 = 0xBD

      // Write mem[0] = 0x10
      ui_in[3:0] = 4'd0;  // Address
      uio_in     = 8'h10; // Data
      #10;               // Wait 1 clock cycle in simulation

      // Write mem[1] = 0x42
      ui_in[3:0] = 4'd1;
      uio_in     = 8'h42;
      #10;

      // Write mem[2] = 0x70
      ui_in[3:0] = 4'd2;
      uio_in     = 8'h70;
      #10;

      // Write mem[3] = 0x00
      ui_in[3:0] = 4'd3;
      uio_in     = 8'h00;
      #10;

      // Done loading -> switch to run mode
      ui_in[7] = 1'b0;
      #10;

      // ------------------------------------------------------------------
      // RUN MODE: let CPU fetch & execute
      // ------------------------------------------------------------------
      // Wait enough cycles to fetch & run the instructions
      #50;

      // Check final ACC result on uo_out
      if (uo_out == 8'hBD) begin
          $display("TEST PASS: ACC == 0xBD as expected!");
      end
      else begin
          $display("TEST FAIL: ACC == 0x%h, expected 0xBD", uo_out);
      end

      // Finish simulation
      $finish;
  end

endmodule
