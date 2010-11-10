%%% File    : ibrowse_test_server.erl
%%% Author  : Chandrashekhar Mullaparthi <chandrashekhar.mullaparthi@t-mobile.co.uk>
%%% Description : A server to simulate various test scenarios
%%% Created : 17 Oct 2010 by Chandrashekhar Mullaparthi <chandrashekhar.mullaparthi@t-mobile.co.uk>

-module(ibrowse_test_server).
-export([
         start_server/2,
         stop_server/1
        ]).

-record(request, {method, uri, version, headers = [], body = []}).

start_server(Port, Sock_type) ->
    Fun = fun() ->
                  register(server_proc_name(Port), self()),
                  case do_listen(Sock_type, Port, [{active, false},
                                                   {packet, http}]) of
                      {ok, Sock} ->
                          do_trace("Server listening on port: ~p~n", [Port]),
                          accept_loop(Sock, Sock_type);
                      Err ->
                          do_trace("Failed to start server on port ~p. ~p~n",
                                   [Port, Err]),
                          Err
                  end
          end,
    spawn(Fun).

stop_server(Port) ->
    exit(whereis(server_proc_name(Port)), kill).

server_proc_name(Port) ->
    list_to_atom("ibrowse_test_server_"++integer_to_list(Port)).

do_listen(tcp, Port, Opts) ->
    gen_tcp:listen(Port, Opts);
do_listen(ssl, Port, Opts) ->
    application:start(crypto),
    application:start(ssl),
    ssl:listen(Port, Opts).

do_accept(tcp, Listen_sock) ->
    gen_tcp:accept(Listen_sock);
do_accept(ssl, Listen_sock) ->
    ssl:ssl_accept(Listen_sock).

accept_loop(Sock, Sock_type) ->
    case do_accept(Sock_type, Sock) of
        {ok, Conn} ->
            Pid = spawn_link(
              fun() ->
                      server_loop(Conn, Sock_type, #request{})
              end),
            set_controlling_process(Conn, Sock_type, Pid),
            Pid ! {setopts, [{active, true}]},
            accept_loop(Sock, Sock_type);
        Err ->
            Err
    end.

set_controlling_process(Sock, tcp, Pid) ->
    gen_tcp:controlling_process(Sock, Pid);
set_controlling_process(Sock, ssl, Pid) ->
    ssl:controlling_process(Sock, Pid).

setopts(Sock, tcp, Opts) ->
    inet:setopts(Sock, Opts);
setopts(Sock, ssl, Opts) ->
    ssl:setopts(Sock, Opts).

server_loop(Sock, Sock_type, #request{headers = Headers} = Req) ->
    receive
        {http, Sock, {http_request, HttpMethod, HttpUri, HttpVersion}} ->
            server_loop(Sock, Sock_type, Req#request{method = HttpMethod,
                                                     uri = HttpUri,
                                                     version = HttpVersion});
        {http, Sock, {http_header, _, _, _, _} = H} ->
            server_loop(Sock, Sock_type, Req#request{headers = [H | Headers]});
        {http, Sock, http_eoh} ->
            process_request(Sock, Sock_type, Req),
            server_loop(Sock, Sock_type, #request{});
        {http, Sock, {http_error, Err}} ->
            do_trace("Error parsing HTTP request:~n"
                     "Req so far : ~p~n"
                     "Err        : ", [Req, Err]),
            exit({http_error, Err});
        {setopts, Opts} ->
            setopts(Sock, Sock_type, Opts),
            server_loop(Sock, Sock_type, Req);
        Other ->
            do_trace("Recvd unknown msg: ~p~n", [Other]),
            exit({unknown_msg, Other})
    after 5000 ->
            do_trace("Timing out client connection~n", []),
            ok
    end.

do_trace(Fmt, Args) ->
    io:format("~s -- " ++ Fmt, [ibrowse_lib:printable_date() | Args]).

process_request(Sock, Sock_type, Req) ->
    do_trace("Recvd req: ~p~n", [Req]),
    Resp = <<"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n">>,
    do_send(Sock, Sock_type, Resp).

do_send(Sock, tcp, Resp) ->
    ok = gen_tcp:send(Sock, Resp);
do_send(Sock, ssl, Resp) ->
    ok = ssl:send(Sock, Resp).