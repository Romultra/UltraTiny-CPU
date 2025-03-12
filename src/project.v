/*
 * Copyright (c) 2024 Roméo Estezet
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ultra_tiny_cpu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  //-------------------------------------------------------------------------
  // I/O Wiring
  //-------------------------------------------------------------------------
  // We will expose the accumulator on uo_out:
  // (Could choose something else, but ACC is typical.)
  reg [7:0] acc_out;
  assign uo_out = acc_out;

  //-------------------------------------------------------------------------
  // CPU Internal Registers
  //-------------------------------------------------------------------------
  reg [7:0] ACC;    // Accumulator
  reg [7:0] B;      // General-purpose register
  reg [2:0] PC;     // Program counter
  reg [7:0] IR;     // Instruction register

  //-------------------------------------------------------------------------
  // Tiny Memory (8 bytes)
  //-------------------------------------------------------------------------
  reg [7:0] mem [0:7]; 
  integer i;
  
  // Optional: Initialize memory to zero to avoid 'X' in simulation or hardware
  initial begin
      for (i = 0; i < 7; i = i + 1)
          mem[i] = 8'h00;
      // You could hard-code some instructions here as an example:
      // mem[0] = 8'h12; // example instruction, etc.
  end

  //-------------------------------------------------------------------------
  // CPU State Machine
  //-------------------------------------------------------------------------
  // Simple states: FETCH, EXECUTE. 
  // A real design often uses multiple states for "fetch next byte" in immediate instructions, etc.
  localparam S_FETCH   = 2'b00;
  localparam S_DECODE  = 2'b01;
  localparam S_EXECUTE = 2'b10;
  localparam S_WAIT    = 2'b11;  // used briefly for multi-cycle ops if needed

  reg [1:0] state; 

  //-------------------------------------------------------------------------
  // Synchronous Logic
  //-------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          // Asynchronous reset
          ACC   <= 8'b0;
          B     <= 8'b0;
          PC    <= 3'b0;
          IR    <= 8'b0;
          acc_out <= 8'b0;
          state <= S_FETCH;
      end 
      else begin
          // If not enabled or if in "load program mode", 
          // we skip normal CPU operation.
          if (!ena) begin
              // Keep outputs at known state
              acc_out <= ACC;
              state <= S_FETCH; // Safely hold or re-fetch when re-enabled
          end
          else if (ui_in[7] == 1) begin
              //-------------------------------------------------------------
              // PROGRAM LOAD MODE
              // ui_in[7] == 1 => the 4 LSBs of ui_in is an address, 
              // and we write uio_in into mem at that address.
              //-------------------------------------------------------------
              mem[ui_in[3:0]] <= uio_in;
              // We do not change the CPU registers or run instructions.
              acc_out <= ACC;
          end
          else begin
              //-------------------------------------------------------------
              // NORMAL CPU OPERATION
              //-------------------------------------------------------------
              acc_out <= ACC;  // Keep output updated to ACC each cycle
              case (state)
              //-------------------------------------------------------------
              // FETCH: read instruction from memory[PC], increment PC
              //-------------------------------------------------------------
              S_FETCH: begin
                  IR <= mem[PC[2:0]];
                  PC <= PC + 1'b1;
                  state <= S_DECODE;
              end

              //-------------------------------------------------------------
              // DECODE: can handle immediate fetch if needed
              //-------------------------------------------------------------
              S_DECODE: begin
                  case (IR[7:4])
                      4'h1, // LDA #imm
                      4'h8: // LDB #imm
                      begin
                          // We know the next byte is immediate data
                          // So we do a second fetch next cycle
                          state <= S_WAIT;
                      end

                      // STA addr, LDA addr, JMP, BEQ, etc. use IR[3:0] directly
                      default: begin
                          state <= S_EXECUTE;
                      end
                  endcase
              end

              //-------------------------------------------------------------
              // S_WAIT: used for immediate instructions to fetch immediate data
              //-------------------------------------------------------------
              S_WAIT: begin
                  // IR said "LDA #imm" or "LDB #imm"
                  // The next byte in memory is the immediate operand
                  reg [7:0] imm_data; // this is not optimized
                  imm_data = mem[PC[2:0]];
                  PC <= PC + 1'b1;

                  if (IR[7:4] == 4'h1) begin
                      // LDA #imm
                      ACC <= imm_data;
                  end 
                  else if (IR[7:4] == 4'h8) begin
                      // LDB #imm
                      B <= imm_data;
                  end

                  state <= S_EXECUTE;
              end

              //-------------------------------------------------------------
              // EXECUTE: ALU or memory ops or branch
              //-------------------------------------------------------------
              S_EXECUTE: begin
                  case (IR[7:4])
                      4'h0: // NOP
                          /* no-op */;

                      4'h2: // ADD B
                          ACC <= ACC + B;

                      4'h3: // SUB B
                          ACC <= ACC - B;

                      4'h4: // AND B
                          ACC <= ACC & B;

                      4'h5: // OR B
                          ACC <= ACC | B;

                      4'h6: // XOR B
                          ACC <= ACC ^ B;

                      4'h7: // NOT ACC
                          ACC <= ~ACC;

                      // (4'h1 and 4'h8 were handled in S_WAIT to fetch imm)

                      4'h9: begin // STA [4-bit addr]
                          mem[IR[3:0]] <= ACC;
                      end

                      4'hA: begin // LDA [4-bit addr]
                          ACC <= mem[IR[3:0]];
                      end

                      4'hB: begin // JMP [4-bit addr]
                          // Jump to low 4 bits => zero-extend to 8 bits
                          PC <= IR[2:0]; 
                      end

                      4'hC: begin // BEQ [4-bit addr]
                          // Branch if ACC == 0
                          if (ACC == 8'b0) begin
                              PC <= IR[2:0]; 
                          end
                      end

                      // Other opcodes not implemented, 
                      // or could be extended here.
                      default: /* do nothing */;
                  endcase

                  // After execute, go back to FETCH
                  state <= S_FETCH;
              end

              endcase
          end
      end
  end

endmodule
