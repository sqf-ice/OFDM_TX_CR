`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    14:04:08 12/04/2012 
// Design Name: 
// Module Name:    IFFT_Mod 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: This module uses the IFFT IP core to modulate the data symbol in OFDM system
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module IFFT_Mod(
	input 			CLK_I, RST_I,
	input [31:0] 	DAT_I,
	input 			CYC_I, WE_I, STB_I, 
	output			ACK_O,
	
	output reg [31:0]	DAT_O,
	output reg			CYC_O, STB_O,
	output				WE_O,
	input					ACK_I,
	
	input [1:0]		STD		// style of standard 00:802.16; 01:802.16; 10:802.22	
    );
reg [31:0]	idat;
//reg [31:0]  odat;
reg			ival;
reg 			icyc;
wire 			out_halt, ena;
wire			datout_ack;
reg			process_done;	// assert when IFFT's procees has done and begin tranmitting data symbol.
reg [11:0] 	d_cnt;			//delay counter to delay generating the preamble in order to wait for IFFT computation

reg [11:0]  pre_delay;		// delay generate the preamble for ifft computing 
reg [39:0]  config_dat;		// configuration data for ifft.
reg 			config_tvalid;
wire  		s_dat_val, s_dat_rdy;
wire			m_dat_val, m_dat_rdy, m_dat_tlast;
wire 	[7:0]	m_index;
wire 			event_status_channel_halt, event_data_in_channel_halt,event_data_out_channel_halt;
wire			aresetn;
//wire			frame_start;
wire	[31:0] fft_datout;

assign 	out_halt   = STB_O & (~ACK_I);
assign 	datout_ack = STB_O & ACK_I;
assign 	ena 		= CYC_I & STB_I & WE_I;
assign 	ACK_O 	= ena & (~out_halt) & (s_dat_rdy) ;
	 
always @(posedge CLK_I) begin
	if(RST_I) 			idat<= 32'd0;
	else if(ACK_O) 	idat <= DAT_I;
end
always @(posedge CLK_I) begin
	if(RST_I) 		ival <= 1'b0;
	else if(ena)	ival <= 1'b1;
	else				ival <= 1'b0;
end

always @(posedge CLK_I)
begin
	if(RST_I)		icyc <= 1'b0;		
	else				icyc <= CYC_I;	
end
always @(posedge CLK_I)
begin
	if(RST_I)													CYC_O <= 1'b0;		
	else if(d_cnt == pre_delay)							CYC_O <= 1'b1;	
	else if((~CYC_I) &(~m_dat_val) &	process_done)	CYC_O <= 1'b0;
end

always @(posedge CLK_I)
begin
	if(RST_I)										d_cnt <= 12'd0;		
	else if(  CYC_I  &(~icyc))					d_cnt <= 12'd0;	
	else if(CYC_I &(~(d_cnt == 12'd1677)))	d_cnt <= d_cnt + 1'd1;
end

always @(posedge CLK_I)
begin
	if(RST_I)									process_done <= 1'b0;		
	else if(CYC_I &(~icyc))					process_done <= 1'b0;	
	else if(m_dat_val)						process_done <= 1'b1;
end

always @(posedge CLK_I)
begin
	if(RST_I)									DAT_O <= 32'd0; 	
	else if (m_dat_rdy & (~out_halt))	DAT_O <= fft_datout;		
end
always @(posedge CLK_I)
begin
	if(RST_I)									STB_O <= 1'b0; 	
	else if (m_dat_rdy & (~out_halt))	STB_O <= m_dat_val;	
end
assign	WE_O			= STB_O;


assign		aresetn 	= ~RST_I;
assign   	s_dat_val	= ival & (~out_halt);
assign		m_dat_rdy 	= ~out_halt;

// [39 : 0] s_axis_config_tdata: [36:25] scale; [24]fwd_inv; [18:8]: cp_len; [4:0]:nfft
// 802.11:
// 	scale: shift right 6 bits :  1, 2, 3; 				inv = 0; cp_len = 1/4 (010 0000 0000); nfft = 64(0 0110) 
// 	config_tdata = 0000 0000 0011 0110 0000 0000 0001 0000 0000 0110
// 802.16:
// 	scale: shift right 12 bits :  1, 2, 2, 3; 		inv = 0; cp_len = 1/8 (001 0000 0000); nfft = 256(0 1000)
// 	config_tdata = 0000 0000 1101 0110 0000 0001 0000 0000 0000 1000
// 802.22:
// 	scale: shift right 12 bits :  1, 1, 2, 2, 2, 3; inv = 0; cp_len = 1/4(010 0000 0000); nfft = 2048(0 1011)
// 	config_tdata = 0000 1011 0101 0110 0000 0010 0000 0000 0000 1011
always@(*) begin
	case (STD)
		2'b00: begin
						config_dat = 40'h0036020006;
						pre_delay  = 12'd7;
				end
		2'b01: begin
						config_dat = 40'h00D6010008;
						pre_delay  = 12'd57;
				end
		2'b10: begin
						config_dat = 40'h0B5602000B;
						pre_delay  = 12'd1676;
				end
		2'b11: begin
						config_dat = 40'd0;
						pre_delay  = 12'd0;
				end
		default: begin
						config_dat = 40'd0;
						pre_delay  = 12'd0;
				end
	endcase
end

always @(posedge CLK_I)
begin
	if(RST_I)						config_tvalid <= 1'b0;		
	else if(CYC_I&(~icyc))		config_tvalid <= 1'b1;	
	else 								config_tvalid <= 1'b0;
end

wire [15:0] m_data_tuser;
wire 			config_tready;
IFFT IFFT_Ins(
	.aclk(CLK_I), 											// input aclk
	//.aclken(aclken), 									// input aclken
	.aresetn(aresetn), 									// input aresetn
	.s_axis_config_tdata(config_dat),				
	.s_axis_config_tvalid(config_tvalid), 			// input s_axis_config_tvalid
	.s_axis_config_tready(config_tready), 			// ouput s_axis_config_tready
	.s_axis_data_tdata(idat), 							// input [31 : 0] s_axis_data_tdata
	.s_axis_data_tvalid(s_dat_val),					// input s_axis_data_tvalid
	.s_axis_data_tready(s_dat_rdy), 					// ouput s_axis_data_tready
	.s_axis_data_tlast(1'b0), 							// input s_axis_data_tlast
	.m_axis_data_tdata(fft_datout), 					// ouput [31 : 0] m_axis_data_tdata
	.m_axis_data_tuser(m_data_tuser), 				// ouput [15 : 0] m_axis_data_tuser
	.m_axis_data_tvalid(m_dat_val), 					// ouput m_axis_data_tvalid
	.m_axis_data_tready(m_dat_rdy), 					// input m_axis_data_tready
	.m_axis_data_tlast(m_dat_tlast),					// ouput m_axis_data_tlast
	.event_frame_started(event_frame_started), 	// ouput event_frame_started
	.event_tlast_unexpected(), 						// ouput event_tlast_unexpected
	.event_tlast_missing(), 							// ouput event_tlast_missing
	.event_status_channel_halt(event_status_channel_halt), // ouput event_status_channel_halt
	.event_data_in_channel_halt(event_data_in_channel_halt), // ouput event_data_in_channel_halt
	.event_data_out_channel_halt(event_data_out_channel_halt)); // ouput event_data_out_channel_halt
endmodule
	