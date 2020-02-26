// Copyright (c) 2020 Sonal Pinto
// SPDX-License-Identifier: Apache-2.0


/*
Kronos RISC-V 32I Decoder
The 32b instruction and PC from the IF stage is decoded
into a generic form:

    RESULT1 = ALU( OP1, OP2 )
    RESULT2 = ADD( OP3, OP4 )
    WB_CONTROLS

where,
    OP1-4       : Operands, where OP1/2 are primary kronos_ALU operands,
                  and OP3/4 are secondary adder operands
                  Each operand can take one of many values as listed below,
                  OP1 <= PC, ZERO, REG[rs1]
                  OP2 <= IMM, FOUR, REG[rs2]
                  OP3 <= REG[rs1], PC, ZERO
                  OP4 <= REG[rs2], IMM
    EX_CTRL     : Execute stage controls
    WB_CTRL     : Write back stage controls which perform an action using
                  RESULT1/2
    RESULT1     : register write data
                  memory access address
                  branch condition
    RESULT2     : memory write data
                  branch target

EX_CTRL,
    cin, rev, uns , eq, inv, align, sel  
    Check kronos_alu for details

WB_CTRL
    rd, rd_write, branch, branch_cond, ld, st, data_size, data_uns, illegal


Note: The 4 operand requirement comes from the RISC-V's Branch instructions which perform
    if compare(rs1, rs2):
        pc <= pc + Imm

    Which consumes rs1, rs2, pc and Imm at the same time!
*/


module kronos_ID
    import kronos_types::*;
(
    input  logic        clk,
    input  logic        rstz,
    input  logic        flush,
    // IF/ID
    input  pipeIFID_t   fetch,
    input  logic        pipe_in_vld,
    output logic        pipe_in_rdy,
    // ID/EX
    output pipeIDEX_t   decode,
    output logic        pipe_out_vld,
    input  logic        pipe_out_rdy,
    // REG Write
    input  logic [31:0] regwr_data,
    input  logic [4:0]  regwr_sel,
    input  logic        regwr_en
);

logic [31:0] IR, PC;
logic [4:0] OP;
logic [6:0] opcode;
logic [4:0] rs1, rs2, rd;
logic [2:0] funct3;
logic [6:0] funct7;

logic is_nop;

logic is_illegal;
logic instr_valid;
logic illegal_opcode;

logic regrd_rs1_en, regrd_rs2_en;
logic [31:0] regrd_rs1, regrd_rs2;
logic regwr_rd_en;

logic sign;
logic format_I;
logic format_J;
logic format_S;
logic format_B;
logic format_U;

// Immediate Operand segments
// A: [0]
// B: [4:1]
// C: [10:5]
// D: [11]
// E: [19:12]
// F: [31:20]
logic           ImmA;
logic [3:0]     ImmB;
logic [5:0]     ImmC;
logic           ImmD;
logic [7:0]     ImmE;
logic [11:0]    ImmF;

logic [31:0] immediate;

// Execute Stage controls
logic       cin;
logic       rev;
logic       uns;
logic       eq;
logic       inv;
logic       align;
logic [2:0] sel;

// Memory access controls
logic [1:0] mem_access_size;
logic mem_access_unsigned;

// Hazard controls
logic hcu_upgrade;
logic hcu_downgrade;
logic hcu_stall;


// ============================================================
// [rv32i] Instruction Decoder

assign IR = fetch.ir;
assign PC = fetch.pc;

// Aliases to IR segments
assign opcode = IR[6:0];
assign OP = opcode[6:2];

assign rs1 = IR[19:15];
assign rs2 = IR[24:20];
assign rd  = IR[11: 7];

assign funct3 = IR[14:12];
assign funct7 = IR[31:25];

// opcode is illegal if LSB 2b are not 2'b11
assign illegal_opcode = opcode[1:0] != 2'b11;


// ============================================================
// Integer Registers

/*
Note: Since this ID module is geared towards FPGA, 
    Dual-Port Embedded Block Ram will be used to implement the 32x32 registers.
    Register (EBR) access is clocked. We need to read two registers on 
    the off-edge to have it ready by the next active edge.

    In the iCE40UP5K this would inefficiently take 4 EBR (each being 16x256)
*/

logic [31:0] REG1 [32] /* synthesis syn_ramstyle = "no_rw_check" */;
logic [31:0] REG2 [32] /* synthesis syn_ramstyle = "no_rw_check" */;

assign regrd_rs1_en = OP == INSTR_OPIMM 
                    || OP == INSTR_OP 
                    || OP == INSTR_JALR 
                    || OP == INSTR_BR
                    || OP == INSTR_LOAD
                    || OP == INSTR_STORE;

assign regrd_rs2_en = OP == INSTR_OP 
                    || OP == INSTR_BR
                    || OP == INSTR_STORE;

assign regwr_rd_en = (rd != 0) && (OP == INSTR_LUI
                                || OP == INSTR_AUIPC
                                || OP == INSTR_JAL
                                || OP == INSTR_JALR
                                || OP == INSTR_OPIMM 
                                || OP == INSTR_OP
                                || OP == INSTR_LOAD);

// REG read
always_ff @(negedge clk) begin
    if (regrd_rs1_en) regrd_rs1 <= (rs1 != 0) ? REG1[rs1] : '0;
    if (regrd_rs2_en) regrd_rs2 <= (rs2 != 0) ? REG2[rs2] : '0;
end

// REG Write
always_ff @(posedge clk) begin
    if (regwr_en) begin
        REG1[regwr_sel] <= regwr_data;
        REG2[regwr_sel] <= regwr_data;
    end
end


// ============================================================
// Immediate Decoder

assign sign = IR[31];

always_comb begin
    // Instruction format --- used to decode Immediate 
    format_I = OP == INSTR_OPIMM || OP == INSTR_JALR || OP == INSTR_LOAD;
    format_J = OP == INSTR_JAL;
    format_S = OP == INSTR_STORE;
    format_B = OP == INSTR_BR;
    format_U = OP == INSTR_LUI || OP == INSTR_AUIPC;

    // Immediate Segment A - [0]
    if (format_I) ImmA = IR[20];
    else if (format_S) ImmA = IR[7];
    else ImmA = 1'b0; // B/J/U
    
    // Immediate Segment B - [4:1]
    if (format_U) ImmB = 4'b0;
    else if (format_I || format_J) ImmB = IR[24:21];
    else ImmB = IR[11:8]; // S/B

    // Immediate Segment C - [10:5]
    if (format_U) ImmC = 6'b0;
    else ImmC = IR[30:25];

    // Immediate Segment D - [11]
    if (format_U) ImmD = 1'b0;
    else if (format_B) ImmD = IR[7];
    else if (format_J) ImmD = IR[20];
    else ImmD = sign;

    // Immediate Segment E - [19:12]
    if (format_U || format_J) ImmE = IR[19:12];
    else ImmE = {8{sign}};
    
    // Immediate Segment F - [31:20]
    if (format_U) ImmF = IR[31:20];
    else ImmF = {12{sign}};
end

// As A-Team's Hannibal would say, "I love it when a plan comes together"
assign immediate = {ImmF, ImmE, ImmD, ImmC, ImmB, ImmA};


// ============================================================
// Execute Stage Operation Decoder

always_comb begin
    // Default ALU Operation: ADD 
    //  result1 <= ALU.adder
    //  result2 <= unaligned add
    cin     = 1'b0;
    rev     = 1'b0;
    uns     = 1'b0;
    eq      = 1'b0;
    inv     = 1'b0;
    align   = 1'b0;
    sel     = ALU_ADDER;
    instr_valid = 1'b0;
    is_nop = 1'b0;

    // ALU Controls are decoded using {funct7, funct3, OP}
    /* verilator lint_off CASEINCOMPLETE */
    case(OP)
    // --------------------------------
    INSTR_LUI,
    INSTR_AUIPC,
    INSTR_JAL: instr_valid = 1'b1;
    // --------------------------------
    INSTR_JALR: if (funct3 == 3'b000) begin
        align = 1'b1;
        instr_valid = 1'b1;
    end
    // --------------------------------
    INSTR_BR: begin
        case(funct3)
            3'b000: begin // BEQ
                eq = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
            3'b001: begin // BNE
                eq = 1'b1;
                inv = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
            3'b100: begin // BLT
                cin = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
            3'b101: begin // BGE
                cin = 1'b1;
                inv = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
            3'b110: begin // BLTU
                cin = 1'b1;
                uns = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
            3'b111: begin // BGEU
                cin = 1'b1;
                inv = 1'b1;
                uns = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end
        endcase // funct3
    end
    // --------------------------------
    INSTR_LOAD: begin
        case(funct3)
            3'b000, // LB
            3'b001, // LH
            3'b010, // LW
            3'b100, // LBU
            3'b101: // LHU 
                instr_valid = 1'b1;
        endcase // funct3
    end
    // --------------------------------
    INSTR_STORE: begin
        case(funct3)
            3'b000, // SB
            3'b001, // SH
            3'b010: // SW
                instr_valid = 1'b1;
        endcase // funct3
    end
    // --------------------------------
    INSTR_OPIMM: begin
        case(funct3)
            3'b000: begin // ADDI
                instr_valid = 1'b1;
            end
            3'b010: begin // SLTI
                cin = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end

            3'b011: begin // SLTIU
                cin = 1'b1;
                uns = 1'b1;
                sel = ALU_COMP;
                instr_valid = 1'b1;
            end

            3'b100: begin // XORI
                sel = ALU_XOR;
                instr_valid = 1'b1;
            end

            3'b110: begin // ORI
                sel = ALU_OR;
                instr_valid = 1'b1;
            end

            3'b111: begin // ANDI
                sel = ALU_AND;
                instr_valid = 1'b1;
            end

            3'b001: begin // SLLI
                if (funct7 == 7'd0) begin
                    rev = 1'b1;
                    uns = 1'b1;
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
            end

            3'b101: begin // SRLI/SRAI
                if (funct7 == 7'd0) begin
                    uns = 1'b1;
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
                else if (funct7 == 7'd32) begin
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
            end
        endcase // funct3
    end
    // --------------------------------
    INSTR_OP: begin
        case(funct3)
            3'b000: begin // ADD/SUB
                if (funct7 == 7'd0) begin
                    instr_valid = 1'b1;
                end
                else if (funct7 == 7'd32) begin
                    cin = 1'b1;
                    instr_valid = 1'b1;
                end
            end

            3'b001: begin // SLL
                if (funct7 == 7'd0) begin
                    rev = 1'b1;
                    uns = 1'b1;
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
            end

            3'b010: begin // SLT
                if (funct7 == 7'd0) begin
                    cin = 1'b1;
                    sel = ALU_COMP;
                    instr_valid = 1'b1;
                end
            end

            3'b011: begin // SLTU
                if (funct7 == 7'd0) begin
                    cin = 1'b1;
                    uns = 1'b1;
                    sel = ALU_COMP;
                    instr_valid = 1'b1;
                end
            end

            3'b100: begin // XOR
                if (funct7 == 7'd0) begin
                    sel = ALU_XOR;
                    instr_valid = 1'b1;
                end
            end

            3'b101: begin // SRL/SRA
                if (funct7 == 7'd0) begin
                    uns = 1'b1;
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
                else if (funct7 == 7'd32) begin
                    sel = ALU_SHIFT;
                    instr_valid = 1'b1;
                end
            end

            3'b110: begin // OR
                if (funct7 == 7'd0) begin
                    sel = ALU_OR;
                    instr_valid = 1'b1;
                end
            end

            3'b111: begin // AND
                if (funct7 == 7'd0) begin
                    sel = ALU_AND;
                    instr_valid = 1'b1;
                end
            end
        endcase // funct3
    end
    // --------------------------------
    INSTR_MISC: begin
        case(funct3)
            3'b000: begin // FENCE
                if (funct7[6:3] == '0 && rs1 == '0 && rd =='0) begin
                    is_nop = 1'b1;
                    instr_valid = 1'b1;
                end
            end
            3'b001: begin // FENCE.I
                if (IR[31:20] == '0 && rs1 == '0 && rd =='0) begin
                    is_nop = 1'b1;
                    instr_valid = 1'b1;
                end
            end
        endcase // funct3
    end
    endcase // OP
    /* verilator lint_on CASEINCOMPLETE */
end

// Consolidate illegal factors
assign is_illegal = ~(instr_valid) | illegal_opcode;


// ============================================================
// Memory Access
// Load/Store memory access control
assign mem_access_size = (OP == INSTR_LOAD || OP == INSTR_STORE) ? funct3[1:0] : '0;
assign mem_access_unsigned = (OP == INSTR_LOAD || OP == INSTR_STORE) ? funct3[2] : '0;


// ============================================================
// Hazard Control

assign hcu_upgrade = regwr_rd_en && pipe_in_vld && pipe_in_rdy && ~is_illegal;
assign hcu_downgrade = regwr_en;

kronos_hcu u_hcu (
    .clk         (clk          ),
    .rstz        (rstz         ),
    .flush       (flush        ),
    .rs1         (rs1          ),
    .rs2         (rs2          ),
    .rd          (rd           ),
    .regrd_rs1_en(regrd_rs1_en ),
    .regrd_rs2_en(regrd_rs2_en ),
    .upgrade     (hcu_upgrade  ),
    .regwr_sel   (regwr_sel    ),
    .downgrade   (hcu_downgrade),
    .stall       (hcu_stall    )
);


// ============================================================
// Instruction Decode Output Pipe (decoded instruction)

always_ff @(posedge clk or negedge rstz) begin
    if (~rstz) begin
        pipe_out_vld <= 1'b0;
    end
    else begin
        if (flush) begin
            pipe_out_vld <= 1'b0;
        end
        else if(pipe_in_vld && pipe_in_rdy) begin
            pipe_out_vld <= ~is_nop;

            // EX controls
            decode.cin   <= cin;
            decode.rev   <= rev;
            decode.uns   <= uns;
            decode.eq    <= eq;
            decode.inv   <= inv;
            decode.align <= align;
            decode.sel   <= sel;
            
            // WB controls
            decode.rd           <= (regwr_rd_en) ? rd : '0;
            decode.rd_write     <= regwr_rd_en;
            decode.branch       <= OP == INSTR_JAL || OP == INSTR_JALR;
            decode.branch_cond  <= OP == INSTR_BR;
            decode.ld           <= OP == INSTR_LOAD;
            decode.st           <= OP == INSTR_STORE;
            decode.data_size    <= mem_access_size;
            decode.data_uns     <= mem_access_unsigned;
            decode.illegal      <= is_illegal;

            // Store defaults in operands
            decode.op1 <= PC;
            decode.op2 <= FOUR;
            decode.op3 <= PC;
            decode.op4 <= ZERO;

            // Fill out OP1-4 as per opcode
            /* verilator lint_off CASEINCOMPLETE */
            case(OP)
                INSTR_LUI   : begin
                    decode.op1 <= ZERO;
                    decode.op2 <= immediate;
                end
                INSTR_AUIPC : begin
                    decode.op2 <= immediate;
                end
                INSTR_JAL : begin
                    decode.op4 <= immediate;
                end
                INSTR_JALR : begin
                    decode.op3 <= regrd_rs1;
                    decode.op4 <= immediate;
                end
                INSTR_BR: begin
                    decode.op1 <= regrd_rs1;
                    decode.op2 <= regrd_rs2;
                    decode.op4 <= immediate;
                end
                INSTR_LOAD: begin
                    decode.op1 <= regrd_rs1;
                    decode.op2 <= immediate;
                end
                INSTR_STORE: begin
                    decode.op1 <= regrd_rs1;
                    decode.op2 <= immediate;
                    decode.op3 <= ZERO;
                    decode.op4 <= regrd_rs2;
                end
                INSTR_OPIMM : begin
                    decode.op1 <= regrd_rs1;
                    decode.op2 <= immediate;
                end
                INSTR_OP    : begin
                    decode.op1 <= regrd_rs1;
                    decode.op2 <= regrd_rs2;
                end
            endcase // OP
            /* verilator lint_off CASEINCOMPLETE */

        end
        else if (pipe_out_vld && pipe_out_rdy) begin
            pipe_out_vld <= 1'b0;
        end
    end
end

// Pipethru can only happen in the ID1 state
assign pipe_in_rdy = (~pipe_out_vld | pipe_out_rdy) && ~hcu_stall;

endmodule
