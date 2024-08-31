
module tb_top;

logic clk, rstz;

logic [31:0] instr_addr;
logic [31:0] instr_data;
logic instr_req;
logic instr_ack;
logic [31:0] data_addr;
logic [31:0] data_rd_data;
logic [31:0] data_wr_data;
logic [3:0] data_mask;
logic data_wr_en;
logic data_req;
logic data_ack;
// ============================================================
// Kronos
// ============================================================

kronos_core #(
  .BOOT_ADDR(32'h0),
  .FAST_BRANCH(1),
  .EN_COUNTERS(1),
  .EN_COUNTERS64B(1),
  .CATCH_ILLEGAL_INSTR(1),
  .CATCH_MISALIGNED_JMP(0),
  .CATCH_MISALIGNED_LDST(0)
) u_core (
  .clk               (clk         ),
  .rstz              (rstz        ),
  .instr_addr        (instr_addr  ),
  .instr_data        (instr_data  ),
  .instr_req         (  ),
  .instr_ack         (1'b1   ),
  .data_addr         (data_addr   ),
  .data_rd_data      (data_rd_data),
  .data_wr_data      (),
  .data_mask         (data_mask   ),
  .data_wr_en        (data_wr_en  ),
  .data_req          (   ),
  .data_ack          (1'b1    ),
  .software_interrupt(1'b0        ),
  .timer_interrupt   (1'b0        ),
  .external_interrupt(1'b0        )
);

initial begin
  clk = 0;
  rstz = 0;

  fork
    forever #1ns clk = ~clk;
  join_none

  data_rd_data = 32'h00080AA8;

end

default clocking cb @(posedge clk); endclocking

// !!! Change this parameter to run either the fast or the slow test
localparam logic fast = 0;

always @(posedge clk) begin

  ##4 rstz = 1;

  // Start with one cycle delay, because Kronos does not take the instruction in the first cycle after reset
  ##1

  for (int i = 0; i < 1; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  // Load some data from memory that will unexpectedly end up in mtvec
  // lw      t6, 16(t4) will load data_rd_data into t6
  instr_data <= 32'h10eaf83;
  if (fast == 1)
    data_rd_data <= 32'b0;
  else
    data_rd_data <= '1; // all ones
  ##1

  // some NOPs
  for (int i = 0; i < 1; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  //csrw	mtval,gp     // an unrelated csr write
  instr_data <= 32'h34319073;
  ##1

  // NOP
  instr_data <= 32'h00000013;
  ##1

  //addi    t0, t6, -1278 -----> the malicious addi
  instr_data <= 32'hb02f8293;
  ##1


  // csrw	mtval,gp     // an unrelated csr write
  instr_data <= 32'h34319073;
  ##1

  //c.jr    s5
  instr_data <= 32'h34038a82;
  // data_rd_data <= 32'h0;
  ##1

  //beq     s5, s5, pc + 2048
  instr_data <= 32'h15a80e3;
  ##1

  // //
  instr_data <= 32'h4160078;
  ##1;

    // end with some random instructions for delay emonstration
  for (int i = 0; i < 10; i++) begin
    // NOP
    instr_data <= 32'h00000013;
    ##1;

    // lui	t1,0x10
    instr_data <= 32'h00010337;
    ##1;

    // addi	t1,t1,1
    instr_data <= 32'h00130313;
    ##1;

    // addi	t1,t1,1
    instr_data <= 32'h00130313;
    ##1;

    // addi	t1,t1,1
    instr_data <= 32'h00130313;
    ##1;

  end
end

endmodule