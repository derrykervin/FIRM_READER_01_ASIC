`timescale 1ns/1ps
module tb_reader_internal_faults;
    parameter CPB=16;
    reg clk=0, reset_n=1, detect=0;
    wire crst, tx, busy, pass, fail;
    wire [63:0] response;
    wire [2:0] error;
    wire [3:0] state;
    firm_reader_01 #(.UART_CLKS_PER_BIT(CPB)) dut(
        .clk(clk),.reset_n(reset_n),.card_detect(detect),.uart_rx(1'b1),
        .card_present(),.card_clk(),.card_reset_n(crst),.uart_tx(tx),
        .busy(busy),.auth_pass(pass),.auth_fail(fail),.card_version(),
        .card_id(),.auth_response(response),.error_code(error),.state_debug(state));
    always #5 clk=~clk;
    task insert_to_send;
        begin
            @(negedge clk); detect=1;
            wait(state==4'd3);
            @(negedge clk);
        end
    endtask
    task check_failure;
        begin
            repeat(3) @(negedge clk);
            if(state!==10 || busy!==0 || pass!==0 || fail!==1 ||
               error!==4 || crst!==0 || tx!==1 || response!==0)
                $fatal(1,"Internal fault did not fail closed state=%d error=%d",state,error);
            repeat(20) @(negedge clk);
            if(state!==10 || pass!==0 || fail!==1 || error!==4 || crst!==0)
                $fatal(1,"Internal error was not sticky");
            detect=0; repeat(8) @(negedge clk);
            if(state!==0 || fail!==0 || pass!==0 || error!==0)
                $fatal(1,"Removal did not clear internal failure");
        end
    endtask
    initial begin
        #1 reset_n=0;
        repeat(5) @(negedge clk); reset_n=1;
        insert_to_send;
        // Invalid phase with a stale success and DONE state must revoke success.
        force dut.phase=2'd3; force dut.state=4'd9; force dut.auth_pass=1'b1;
        @(negedge clk);
        release dut.phase; release dut.state; release dut.auth_pass;
        check_failure;
        insert_to_send;
        force dut.state=4'd15;
        @(negedge clk); release dut.state;
        check_failure;
        insert_to_send;
        // Index overflow must not initiate out-of-range challenge extraction.
        force dut.phase=2'd2; force dut.tx_index=4'd9;
        @(negedge clk); release dut.phase; release dut.tx_index;
        check_failure;
        insert_to_send;
        if(fail!==0 || pass!==0 || crst!==1) $fatal(1,"Reinsertion recovery failed");
        reset_n=0; repeat(5) @(negedge clk);
        if(fail!==0 || pass!==0 || error!==0 || crst!==0)
            $fatal(1,"Global reset recovery failed");
        $display("PASS Reader internal fault guard CPB=%0d",CPB); $finish;
    end
    initial begin #(10*(CPB*1000+20000)); $fatal(1,"Internal fault test timeout"); end
endmodule
