`timescale 1ns/1ps
module tb_reader_faults;
    parameter CPB=16;
    reg clk=0, reset_n=0, detect=0, flip=0;
    integer mode=0, frames=0;
    wire cclk, crst, rtx, ctx, link_rx, pass, fail, busy;
    wire [63:0] id,response;
    wire [2:0] error;
    assign link_rx=(mode==3 || (mode==4 && frames>=12)) ? 1'b1 : ctx ^ flip;
    firm_reader_01 #(.UART_CLKS_PER_BIT(CPB)) reader(
        .clk(clk),.reset_n(reset_n),.card_detect(detect),.card_present(),
        .card_clk(cclk),.card_reset_n(crst),.uart_tx(rtx),.uart_rx(link_rx),
        .busy(busy),.auth_pass(pass),.auth_fail(fail),.card_version(),
        .card_id(id),.auth_response(response),.error_code(error),.state_debug());
    card #(.UART_CLKS_PER_BIT(CPB)) card_dut(
        .clk(cclk),.reset_n(crst),.uart_rx(rtx),.uart_tx(ctx),.gpio_in(8'h0),
        .gpio_out(),.spi_sclk(),.spi_mosi(),.spi_miso(1'b1),.spi_cs_n(),
        .halted(),.debug_pc(),.debug_r0());
    always #10 clk=~clk;
    // Faults are injected on the physical serial wire, not internal Reader state.
    initial forever begin
        @(negedge ctx);
        frames=frames+1;
        #(CPB*20);
        if((mode==1 && frames==1) || (mode==2 && frames==10)) flip=1;
        #(CPB*20); flip=0;
        #(CPB*160);
    end
    task run_failure;
        input integer fault_mode;
        input [2:0] expected_error;
        begin
            @(negedge clk); mode=fault_mode; frames=0; detect=1;
            wait(pass || fail); @(negedge clk);
            if(pass!==0 || fail!==1 || busy!==0 || error!==expected_error)
                $fatal(1,"Fault mode=%0d error=%0d",mode,error);
            if(mode==2 && (id!==64'hF100000000000001 || response!==64'hFFD480C19D70FFA5))
                $fatal(1,"Corrupt response not preserved: %h",response);
            repeat(CPB*25) @(negedge clk);
            if(fail!==1 || pass!==0 || error!==expected_error) $fatal(1,"Failure not sticky");
            detect=0; repeat(CPB*25) @(negedge clk);
            if(pass!==0 || fail!==0 || response!==0 || id!==0 || crst!==0)
                $fatal(1,"Failure removal reset");
            $display("PASS FAULT CPB=%0d MODE=%0d ERROR=%0d",CPB,mode,expected_error);
        end
    endtask
    initial begin #(20*(CPB*5000+100000)); $fatal(1,"Fault test timeout"); end
    initial begin
        repeat(5) @(negedge clk); reset_n=1;
        run_failure(1,1); // wrong version
        run_failure(2,3); // complete but wrong AUTH response
        run_failure(3,2); // no reply
        run_failure(4,2); // truncated AUTH reply
        mode=0; frames=0; detect=1;
        wait(pass || fail); @(negedge clk);
        if(pass!==1 || fail!==0 || response!==64'hFED480C19D70FFA5) $fatal(1,"Recovery failed");
        // Global reset also cancels the completed session, even while card stays in.
        reset_n=0; repeat(5) @(negedge clk);
        if(pass!==0 || fail!==0 || crst!==0 || response!==0) $fatal(1,"Global reset failed");
        reset_n=1; frames=0;
        wait(pass || fail); @(negedge clk);
        if(pass!==1 || fail!==0) $fatal(1,"Global reset restart failed");
        $display("PASS FAULT RECOVERY CPB=%0d",CPB); $finish;
    end
endmodule
