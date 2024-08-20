
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
logic timer_interrupt;
logic external_interrupt;
logic software_interrupt;

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
  .instr_req         (instr_req),
  .instr_ack         (instr_ack  ),
  .data_addr         (data_addr   ),
  .data_rd_data      (data_rd_data),
  .data_wr_data      (),
  .data_mask         (data_mask   ),
  .data_wr_en        (data_wr_en  ),
  .data_req          (   ),
  .data_ack          (1'b1    ),
  .software_interrupt(software_interrupt       ),
  .timer_interrupt   (timer_interrupt),
  .external_interrupt(external_interrupt     )
);

initial begin
  clk = 0;
  rstz = 0;

  fork
    forever #1ns clk = ~clk;
  join_none

  data_rd_data = 32'h00080AAA;

end

default clocking cb @(posedge clk); endclocking

bit [5:0] test_round;
bit toggle;

always @(posedge clk) begin
  if (test_round)
    $display("instr_req = %b, instr_ack = %b, id.fetch_ir = %x, id.rs1 = %d, id.regrd_rs1 = %x, id.regrd_rs2 = %x, id.rs1_forward = %b, u_if.pc_last = %x", instr_req, instr_ack, u_core.u_id.fetch.ir, u_core.u_id.rs1, u_core.u_id.regrd_rs1, u_core.u_id.regrd_rs2, u_core.u_id.rs1_forward, u_core.u_if.pc_last);
end

`define TEST_ROUND_MAX 4

initial begin
  rstz = 0;
  test_round = `TEST_ROUND_MAX;
  ##4
  rstz = 1;
end

always @(posedge clk) begin

// Set up some test values
if (rstz && test_round == `TEST_ROUND_MAX) begin
  instr_data <= 32'hd0000;
  instr_ack <= 1'h0;
  data_rd_data <= 32'h0;
  data_ack <= 1'h0;
  software_interrupt <= 1'h0;
  timer_interrupt <= 1'h0;
  external_interrupt <= 1'h0;

  ##1
  instr_ack <= 1'h1;
  // some NOPs
  for (int i = 0; i < 3; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  instr_data <= 32'h00100093; //	li	ra,1
  ##1
  instr_data <= 32'h00200113; //	li	sp,2
  ##1
  instr_data <= 32'h00300193; //	li	gp,3
  ##1
  instr_data <= 32'h00400213; //	li	tp,4
  ##1
  instr_data <= 32'h00500293; //	li	t0,5
  ##1
  instr_data <= 32'h00600313; //	li	t1,6
  ##1
  instr_data <= 32'h00700393; //	li	t2,7
  ##1
  instr_data <= 32'h00800413; //	li	s0,8
  ##1
  instr_data <= 32'h00900493; //	li	s1,9
  ##1
  instr_data <= 32'h00a00513; //	li	a0,10
  ##1
  instr_data <= 32'h00b00593; //	li	a1,11
  ##1
  instr_data <= 32'h00c00613; //	li	a2,12
  ##1
  instr_data <= 32'h00d00693; //	li	a3,13
  ##1
  instr_data <= 32'h00e00713; //	li	a4,14
  ##1
  instr_data <= 32'h00f00793; //	li	a5,15
  ##1
  instr_data <= 32'h01000813; //	li	a6,16
  ##1
  instr_data <= 32'h01100893; //	li	a7,17
  ##1
  instr_data <= 32'h01200913; //	li	s2,18
  ##1
  instr_data <= 32'h01300993; //	li	s3,19
  ##1
  instr_data <= 32'h01400a13; //	li	s4,20
  ##1
  instr_data <= 32'h01400a13; //	li	s4,20
  ##1
  instr_data <= 32'h01500a93; //	li	s5,21
  ##1
  instr_data <= 32'h01600b13; //	li	s6,22
  ##1
  instr_data <= 32'h01700b93; //	li	s7,23
  ##1
  instr_data <= 32'h01800c13; //	li	s8,24
  ##1
  instr_data <= 32'h01900c93; //	li	s9,25
  ##1
  instr_data <= 32'h01a00d13; //	li	s10,26
  ##1
  instr_data <= 32'h01b00d93; //	li	s11,27
  ##1
  instr_data <= 32'h01c00e13; //	li	t3,28
  ##1
  instr_data <= 32'h01d00e93; //	li	t4,29
  ##1
  instr_data <= 32'h01e00f13; //	li	t5,30
  ##1
  instr_data <= 32'h01f00f93; //	li	t6,31

end

// The test program
if (rstz && test_round) begin

  ##1
  // some NOPs
  for (int i = 0; i < 1; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end


  // The instructions that actually reach the ID stage

  // // 0x0
  // c.unimp
  // // 0x210117
  // auipc   sp, 0x210
  // // 0x413b0863
  // beq     s6, s3, pc + 1040
  // // 0x1910133
  // add     sp, sp, s9
  // // 0x5300167
  // jalr    sp, zero, 83
  // // 0x1510403
  // lb      s0, 21(sp)

  ##1

  ////////

  // Use this instruction to see the bug
  instr_data <= 32'h210117;    // auipc   sp, 0x210

  // Use this instruction to make the bug disappear
  // instr_data <= 32'h210057;    // auipc   x1, 0x210

  ////////

  instr_ack <= 1'h1;
  ##1

  instr_data <= 32'h413b0863;
  ##1

  instr_data <= 32'h1910133;
  ##1

  instr_data <= 32'h410073;
  instr_ack <= 1'h0;  // <<<<<<<<< toggle here between 0 (to see the bug) and 1 (to see jalr behaving correctly)
  ##1

  // A jalr instruction at this clock cycle reads from a wrong register (when the two bug-triggering conditions above are used)
  if (toggle)
    instr_data <= 32'h5308167; // jalr sp, x1, 83 ... (83 = 0x53)
  else
    instr_data <= 32'h5300167; // jalr sp, zero, 83

  toggle = ~toggle;

  instr_ack <= 1'h1;
  ##1

  instr_data <= 32'h1510403;
  ##1

  instr_data <= 32'h1605067;
  ##1

  // some NOPs
  for (int i = 0; i < 4; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  test_round--;
  end


end

endmodule