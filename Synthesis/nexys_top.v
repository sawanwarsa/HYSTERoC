// Board top: 100 MHz in -> MMCM -> 12.5 MHz fabric clock (VCO 800 MHz / 64)
module nexys_top(
    input  wire        clk,
    input  wire        cpu_resetn,
    input  wire [15:0] sw,
    output wire [15:0] led
);
    wire clkfb, clkfb_b, clk_mm, clk_slow, locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .CLKFBOUT_MULT_F(8.0),
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(64.0)
    ) u_mmcm (
        .CLKIN1(clk), .CLKFBIN(clkfb_b), .CLKFBOUT(clkfb),
        .CLKOUT0(clk_mm), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB());

    BUFG u_fb (.I(clkfb),  .O(clkfb_b));
    BUFG u_ck (.I(clk_mm), .O(clk_slow));

    nexys_core u_core (.clk(clk_slow), .cpu_resetn(cpu_resetn & locked), .sw(sw), .led(led));
endmodule
