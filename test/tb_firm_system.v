`timescale 1ns/1ps
module tb_firm_system;
    parameter CPB=16;
    parameter VECTOR=1;
    parameter ALT_ID=0;
    localparam [63:0] CH = VECTOR==0 ? 64'h0 : VECTOR==1 ? 64'h0123456789ABCDEF : 64'hFFFFFFFFFFFFFFFF;
    localparam [63:0] CID = ALT_ID ? 64'h1122334455667788 : 64'hF100000000000001;
    // Known answers copied from the original C1 test, independent of Reader RTL.
    localparam [63:0] KNOWN = VECTOR==0 ? 64'hDD91E74836BD10A4 : VECTOR==1 ? 64'hFED480C19D70FFA5 : 64'h226E18B7C942EF5B;
    localparam [63:0] EXPECTED = KNOWN ^ 64'hF100000000000001 ^ CID;
    reg clk=0, reset_n=0, detect=0;
    wire cclk, crst, rtx, ctx, present, busy, pass, fail, halted;
    wire [7:0] version;
    wire [63:0] id, response;
    wire [2:0] error;
    wire [3:0] state;
    firm_reader_01 #(.UART_CLKS_PER_BIT(CPB),.CHALLENGE(CH)) reader(
        .clk(clk),.reset_n(reset_n),.card_detect(detect),.card_present(present),
        .card_clk(cclk),.card_reset_n(crst),.uart_tx(rtx),.uart_rx(ctx),
        .busy(busy),.auth_pass(pass),.auth_fail(fail),.card_version(version),
        .card_id(id),.auth_response(response),.error_code(error),.state_debug(state));
    card #(.UART_CLKS_PER_BIT(CPB),.CARD_ID(CID)) card_dut(
        .clk(cclk),.reset_n(crst),.uart_rx(rtx),.uart_tx(ctx),
        .gpio_in(8'h0),.gpio_out(),.spi_sclk(),.spi_mosi(),.spi_miso(1'b1),
        .spi_cs_n(),.halted(halted),.debug_pc(),.debug_r0());
    always #10 clk=~clk;
    // Independent UART decoder verifies command ordering and all challenge bytes.
    integer sent=0, b;
    reg [7:0] byte_value, wanted;
    initial forever begin
        @(negedge rtx); #(CPB*10);
        if(rtx!==0) $fatal(1,"Bad Reader start");
        for(b=0;b<8;b=b+1) begin #(CPB*20); byte_value[b]=rtx; end
        #(CPB*20);
        if(crst) begin
            if(rtx!==1) $fatal(1,"Bad Reader stop");
            case(sent%11)
                0: wanted=8'h01;
                1: wanted=8'h02;
                2: wanted=8'h10;
                default: wanted=CH[63-((sent%11)-3)*8 -: 8];
            endcase
            if(byte_value!==wanted) $fatal(1,"Request[%0d]: %h != %h",sent,byte_value,wanted);
            sent=sent+1;
        end
    end
    task remove_card;
        begin
            @(negedge clk); detect=0;
            repeat(8) @(negedge clk);
            if(present!==0 || crst!==0 || cclk!==0 || rtx!==1 || busy!==0 ||
               pass!==0 || fail!==0 || id!==0 || response!==0 || version!==0 || error!==0)
                $fatal(1,"Removal did not reset Reader/session");
            if(card_dut.auth_done!==0 || card_dut.auth_challenge!==0)
                $fatal(1,"Card reset failed");
        end
    endtask
    task await_success;
        begin
            wait(pass || fail); @(negedge clk);
            if(pass!==1 || fail!==0 || error!==0 || busy!==0 || version!==1 ||
               id!==CID || response!==EXPECTED || halted!==0 || card_dut.auth_challenge!==CH)
                $fatal(1,"Bad result: version=%h id=%h response=%h error=%d",version,id,response,error);
            repeat(CPB*25) @(negedge clk);
            if(pass!==1 || fail!==0) $fatal(1,"Result not sticky");
        end
    endtask
    initial begin
        #(20*(CPB*2000+50000)); $fatal(1,"System timeout state=%d",state);
    end
    initial begin
        repeat(5) @(negedge clk); reset_n=1;
        repeat(8) @(negedge clk);
        if(crst!==0 || cclk!==0 || busy!==0) $fatal(1,"Absent state");
        detect=1; await_success;
        if(sent!=11) $fatal(1,"Wrong request length");
        remove_card;
        detect=1; await_success;
        if(sent!=22) $fatal(1,"Reinsertion command count");
        remove_card;
        // Removal in the middle of AUTH, followed by a fresh complete session.
        detect=1;
        wait(card_dut.auth_challenge!==64'd0 || (reader.phase==2 && reader.tx_index==4));
        remove_card;
        repeat(CPB*15) @(negedge clk); sent=0;
        detect=1; await_success;
        if(sent!=11) $fatal(1,"Recovery command count");
        $display("PASS SYSTEM CPB=%0d VECTOR=%0d ALT_ID=%0d: success, remove, reinsert, mid-AUTH removal/recovery",CPB,VECTOR,ALT_ID);
        $finish;
    end
endmodule
