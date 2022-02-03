%% -------------------------------------------------------------------
%%
%% Copyright (c) 2010-2017 Basho Technologies, Inc.
%% Copyright (c) 2009-2010 Gemini Mobile Technologies, Inc.  All rights reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(cluster_info).

-behaviour(application).

%% application callbacks
%% Note: It is *not* necessary to start this application as a real/true OTP
%%       application before you can use it.  The application behavior here
%%       is only to help integrate this code nicely into OTP-style packaging.
-export([start/0, start/2, stop/1]).
-export([start_phase/3, prep_stop/1, config_change/3]).

-export([register_app/1,
         dump_node/2, dump_node/3,
         dump_local_node/1, dump_local_node/2,
         dump_all_connected/1, dump_all_connected/2,
         dump_nodes/2, dump_nodes/3,
         list_reports/0, list_reports/1,
         send/2,
         format/2, format/3,
         format_noescape/2, format_noescape/3]).
-export([get_limits/0, reset_limits/0]).

%% Really useful but ugly hack.
-export([capture_io/2]).

-type dump_option() :: {'modules', [atom()]}.
-type dump_return() :: 'ok' | 'error'.
-type filename()    :: string().

-type lnlimit()     :: undefined | pos_integer().
-type lnlimits()    :: {lnlimit(), lnlimit()}.
-type limitfmtfun() :: fun((iolist(), list()) -> iolist()).
-type limitrec()    :: {lnlimits(), limitfmtfun()}.

%% Internal use only, maps to limitrec().
-define(DICT_KEY, '^_^--cluster_info').

%%%----------------------------------------------------------------------
%%% Callback functions from application
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}
%%----------------------------------------------------------------------
-spec start() -> {ok, pid()}.
start() ->
    start(start, []).

-spec start(_,_) -> {ok, pid()}.
start(_Type, _StartArgs) ->
    case application:get_env(?MODULE, skip_basic_registration) of
        undefined ->
            register_app(cluster_info_basic);
        _ ->
            ok
    end,
    {ok, spawn(fun() -> receive pro_forma -> ok end end)}.

%% Lesser-used callbacks....

-spec start_phase(_,_,_) -> 'ok'.
start_phase(_Phase, _StartType, _PhaseArgs) ->
    ok.

-spec prep_stop(_) -> any().
prep_stop(State) ->
    State.

-spec config_change(_,_,_) -> 'ok'.
config_change(_Changed, _New, _Removed) ->
    ok.

%% @doc "Register" an application with the cluster_info app.
%%
%% "Registration" is a misnomer: we're really interested only in
%% having the code server load the callback module, and it's that
%% side-effect with the code server that we rely on later.
-spec register_app(atom()) -> 'ok' | 'undef'.
register_app(CallbackMod) ->
    try
        CallbackMod:cluster_info_init()
    catch
        error:undef ->
            undef
    end.

%% @doc Dump the cluster_info on Node to the specified local File.
-spec dump_node(atom(), filename()) -> dump_return().

dump_node(Node, Path) ->
    dump_node(Node, Path, []).

-spec dump_node(atom(), string(), [dump_option()]) -> dump_return().

dump_node(Node, Path, Opts) when is_atom(Node), is_list(Path) ->
    io:format("Writing report for node ~p\n", [Node]),
    {ok, FH} = file:open(Path, [append]),
    Collector = self(),
    Remote = spawn(Node, fun() ->
        dump_local_info(Collector, Opts),
        collector_done(Collector)
    end),
    MRef = monitor(process, Remote),
    try
        ok = collect_remote_info(Remote, FH)
    catch Class:Reason:Stacktrace ->
        io:format("Error: ~P ~P at ~p\n",
            [Class, 20, Reason, 20, Stacktrace]),
        error
    after
        demonitor(MRef, [flush]),
        catch file:close(FH)
    end.

%% @doc Dump the cluster_info on local node to the specified File.
-spec dump_local_node(filename()) -> [dump_return()].
dump_local_node(Path) ->
    dump_local_node(Path, []).

dump_local_node(Path, Opts) ->
    dump_nodes([node()], Path, Opts).

%% @doc Dump the cluster_info on all connected nodes to the specified
%%      File.
-spec dump_all_connected(filename()) -> [dump_return()].

dump_all_connected(Path) ->
    dump_all_connected(Path, []).

dump_all_connected(Path, Opts) ->
    dump_nodes(lists:sort([node()|nodes()]), Path, Opts).

%% @doc Dump the cluster_info on all specified nodes to the specified
%%      File.
-spec dump_nodes([atom()], filename()) -> [dump_return()].
dump_nodes(Nodes, Path) ->
    dump_nodes(Nodes, Path, []).

dump_nodes(Nodes0, Path, Opts) ->
    Nodes = lists:sort(Nodes0),
    io:format("HTML report is at: ~p:~p\n", [node(), Path]),
    {ok, FH} = file:open(Path, [append]),
    io:format(FH,
        "<!DOCTYPE html>~n<html>~n<head><meta charset=\"UTF-8\">"
        "<title>Cluster Info</title></head>~n<body>", []),
    io:format(FH, "<h1>Node Reports</h1>\n", []),
    io:format(FH, "<ul>\n", []),
    lists:foreach(fun(Node) ->
        io:format(FH,"<li> <a href=\"#~p\">~p</a>\n", [Node, Node])
    end, Nodes),
    io:format(FH, "</ul>\n\n", []),
    _ = file:close(FH),

    Res = [dump_node(Node, Path, Opts) || Node <- Nodes],
    {ok, FH2} = file:open(Path, [append]),
    io:format(FH2, "~n</body>~n</html>~n", []),
    _ = file:close(FH),
    Res.

list_reports() ->
    list_reports("all modules, please").

list_reports(Mod) ->
    GetGens = fun (M) -> try
                             M:cluster_info_generator_funs()
                         catch _:_ ->
                                 []
                         end
              end,
    Filter = fun(X) -> not is_atom(Mod) orelse X == Mod end,
    Mods = [M || {M, _} <- lists:sort(code:all_loaded())],
    lists:flatten([{M, Name} || M <- Mods,
                                Filter(M),
                                {Name, _} <- GetGens(M)]).

format(Pid, Fmt) ->
    format(Pid, Fmt, []).

format(Pid, Fmt, Args) ->
    send(Pid, safe_format(Fmt, Args)).

format_noescape(Pid, Fmt) ->
    format_noescape(Pid, Fmt, []).

format_noescape(Pid, Fmt, Args) ->
    send2(Pid, safe_format(Fmt, Args)).

%%----------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%%----------------------------------------------------------------------
-spec stop(_) -> 'ok'.
stop(_State) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

collect_remote_info(Remote, FH) ->
    receive
        {'DOWN', _, X, Remote, Z} ->
            io:format("Remote error: ~p ~p (~p)\n    -> ~p\n",
                      [X, Remote, node(Remote), Z]),
            ok;
        {collect_data, Remote, IoList} ->
            _ = file:write(FH, IoList),
            collect_remote_info(Remote, FH);
        {collect_data_ack, Remote} ->
            Remote ! collect_data_goahead,
            collect_remote_info(Remote, FH);
        {collect_done, Remote} ->
            ok
    after 120*1000 ->
            timeout
    end.

collector_done(Pid) ->
    Pid ! {collect_done, self()}.

dump_local_info(CPid, Opts) ->
    dbg("D: node = ~p\n", [node()]),
    format(CPid, "\n"),
    format_noescape(CPid, "<a id=\"~p\"> </a>\n", [node()]),
    format_noescape(CPid, "<h1>Local node cluster_info dump, Node: ~p</h1>\n", [node()]),
    format(CPid, "   Options: ~p\n", [Opts]),
    format(CPid, "\n"),
    Mods0 = lists:sort([Mod || {Mod, _Path} <- code:all_loaded()]),
    Filters = proplists:get_value(modules, Opts, [all]),
    Mods = [M || M <- Mods0,
                 lists:member(all, Filters) orelse
                     lists:member(M, Filters)],

    _ = [case (catch Mod:cluster_info_generator_funs()) of
             {'EXIT', _} ->
                 ok;
             NameFuns when is_list(NameFuns) ->
                 format_noescape(CPid, "<ul>\n", []),
                 _ = [begin
                          A = make_anchor(node(), Mod, Name),
                          format_noescape(
                            CPid, "<li><a href=\"#~s\">~s</a></li>\n", [A, Name])
                      end || {Name, _} <- NameFuns],
                 format_noescape(CPid, "</ul><blockquote>", []),
                 _ = [try
                          dbg("D: generator ~p ~s\n", [Fun, Name]),
                          format_noescape(CPid, "\n<a id=\"~s\"></a>\n",
                                          [make_anchor(node(), Mod, Name)]),
                          format_noescape(CPid, "<h2>Report: ~s (~p)</h2>\n\n",
                                          [Name, node()]),
                          format_noescape(CPid, "<pre>\n", []),
                          Fun(CPid)
                      catch Class:Reason:Stacktrace ->
                              format(CPid, "Error in ~p: ~p ~p at ~p\n",
                                     [Name, Class, Reason, Stacktrace])
                      after
                          format_noescape(CPid, "</pre>\n", []),
                          format_noescape(CPid, "\n",[])
                      end || {Name, Fun} <- NameFuns],
                 format_noescape(CPid, "</blockquote>\n", [])
         end || Mod <- Mods],
    ok.

dbg(_Fmt, _Args) ->
    ok.

%%%%%%%%%

%% @doc This is an untidy hack.

-spec capture_io(integer(), function()) -> [term()].
capture_io(Timeout, Fun) ->
    Me = self(),
    spawn(fun() -> capture_io2(Timeout, Fun, Me) end),
    lists:flatten(harvest_reqs(Timeout)).

capture_io2(Timeout, Fun, Parent) ->
    group_leader(self(), self()),
    Fudge = 50,
    Worker = spawn(fun() -> Fun(), timer:sleep(Fudge), Parent ! io_done2 end),
    spawn(fun() -> timer:sleep(Timeout + Fudge + 10), exit(Worker, kill) end),
    get_io_reqs(Parent, Timeout).

get_io_reqs(Parent, Timeout) ->
    receive
        {io_request, From, ReplyAs, Req} ->
            From ! {io_reply, ReplyAs, ok},
            Parent ! {io_data, Req},
            get_io_reqs(Parent, Timeout)
    after Timeout ->
            ok
    end.

harvest_reqs(Timeout) ->
    receive
        {io_data, Req} ->
            case Req of
                {put_chars, _, Mod, Fun, Args} ->
                    [erlang:apply(Mod, Fun, Args)|harvest_reqs(Timeout)];
                {put_chars, _, Chars} ->
                    [Chars|harvest_reqs(Timeout)]
            end;
        io_done ->
            [];
        io_done2 ->
            []
    after Timeout ->
            []
    end.

-spec safe_format(iolist(), list()) -> iolist().
safe_format(Fmt, Args) ->
    {_, LimitedFmt} = get_limit_record(),
    LimitedFmt(Fmt, Args).

%% Not sure why this is exported, but it is ...
-spec get_limits() -> lnlimits().
get_limits() ->
    {Limits, _} = get_limit_record(),
    Limits.

-spec get_limit_record() -> limitrec().
get_limit_record() ->
    case erlang:get(?DICT_KEY) of
        undefined ->
            TruncIO = lager_trunc_io,
            Rec = case code:which(TruncIO) of
                non_existing ->
                    {{undefined, undefined}, fun io_lib:format/2};
                _ ->
                    TMax = get_env(cluster_info, term_max_size, default_size()),
                    FMax = get_env(cluster_info, fmt_max_bytes, default_size()),
                    {{TMax, FMax}, limited_fmt_fun(TruncIO, TMax, FMax)}
            end,
            _ = erlang:put(?DICT_KEY, Rec),
            Rec;
        {{_, _}, _} = Val ->
            Val
    end.

get_env(App, Key, Default) ->
    case application:get_env(App, Key) of
        undefined -> Default;
        {ok, Val} -> Val
    end.

%% Return a function that formats Fmt and Args similar to what io_lib:format/2
%% does but with limits on how large the formatted string may be.
%%
%% If the Args list's size is larger than TermMaxSize, then the formatting is
%% done by TruncIO:print/2, where FmtMaxBytes is used to limit the formatted
%% string's size.
%%
%% TruncIO is assumed to be a module that exports print/2 that works like
%% lager_trunc_io's.
-spec limited_fmt_fun(module(), pos_integer(), pos_integer()) -> limitfmtfun().
limited_fmt_fun(TruncIO, TermMaxSize, FmtMaxBytes) ->
    fun(Fmt, Args) ->
        % When you go looking for it, this is an undocumented API in the
        % kernel that's been marked experimental for years.
        case erts_debug:flat_size(Args) of
            TermSize when TermSize > TermMaxSize ->
                ["Oversize args for format \"", Fmt, "\": \n" | [
                begin
                    {Str, _} = TruncIO:print(lists:nth(N, Args), FmtMaxBytes),
                    ["  arg", integer_to_list(N), ": ", Str, "\n"]
                end || N <- lists:seq(1, erlang:length(Args))
                ]];
            _ ->
                io_lib:format(Fmt, Args)
        end
    end.

reset_limits() -> erlang:erase(?DICT_KEY).

default_size() -> 256*1024.

make_anchor(Node0, Mod, Name) ->
    NameNoSp = re:replace(Name, " ", "", [{return, list}, global]),
    Node = re:replace(atom_to_list(Node0), "'", "", [{return, list}, global]),
    lists:flatten(io_lib:format("~s~w~s", [Node, Mod, NameNoSp])).

send(Pid, IoData) ->
    ReList = [{"&", "\\&amp;"}, {"<", "\\&lt;"}],
    Str = lists:foldl(
        fun({RE, Replace}, Data) ->
            re:replace(Data, RE, Replace, [{return, binary}, global])
        end, IoData, ReList),
    send2(Pid, Str).

send2(Pid, IoData) ->
    Pid ! {collect_data, self(), IoData},
    case incr_counter() rem 10 of
        0 ->
            Pid ! {collect_data_ack, self()},
            receive
                collect_data_goahead ->
                    ok
            after 15*1000 ->
                    ok
            end;
        _ ->
            ok
    end.

incr_counter() ->
    Key = {?MODULE, incr_counter},
    case erlang:get(Key) of
        undefined ->
            erlang:put(Key, 1),
            0;
        N ->
            erlang:put(Key, N+1)
    end.
