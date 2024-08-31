
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
  .EN_COUNTERS64B(0),
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

always @(posedge clk) begin

  ##4 rstz = 1;

  // Start with one cycle delay, because Kronos does not take the instruction in the first cycle after reset
  ##1

  for (int i = 0; i < 1; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  // Load some data from memory that will unexpectedly end up in mtvec
  // lw	s6,0(t1), load the data (we initialized data_rd_data with a constant for testing, so Kronos will read that constant from any memory address)
  instr_data <= 32'h00032b03;
  ##1

  // some NOPs
  for (int i = 0; i < 1; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

  // Alternatively set up a value that we want to sneak into mtvec
  // lui	s6,0x80aaa
  // instr_data <= 32'h80aaab37;
  // ##1

  // First we need an unrelated csr write instruction (may be valid or invalid, as long as it is decoded as csr instruction)
  //csrw	mtval,gp
  instr_data <= 32'h34319073;
  ##1

  // some instruction in the middle, can be any instruction, so we use a NOP
  instr_data <= 32'h00000013;
  ##1

  // !!! the malicious addi (could be an slti as well)
  //addi    ra, s6, 773
  instr_data <= 32'h305b0093; // binary: immediate:1100000101 rs1:10110 funct3: 000 rd:00001 opcode: 0010011
  ##1

  //An illegal instruction that will trigger a trap, to test whether Kronos will execute at the location written into s6 -> it does.
  instr_data <= 32'h30280073;
  ##1

  // end with some NOPs, just to see the fetch addres progressing from s6 onwards
  for (int i = 0; i < 10; i++) begin
    instr_data <= 32'h00000013;
    ##1;
  end

 end

endmodule