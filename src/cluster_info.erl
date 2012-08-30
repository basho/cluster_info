%%%----------------------------------------------------------------------
%%% Copyright: (c) 2009-2010 Gemini Mobile Technologies, Inc.  All rights reserved.
%%% Copyright: (c) 2010-2012 Basho Technologies, Inc.  All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% File     : cluster_info.erl
%%% Purpose  : Cluster info/postmortem data gathering app
%%%----------------------------------------------------------------------

-module(cluster_info).

-behaviour(application).

-define(DICT_KEY, '^_^--cluster_info').

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
         format/2, format/3]).
-export([get_limits/0, reset_limits/0]).

-type dump_option() :: {'modules', [atom()]}.
-type dump_return() :: 'ok' | 'error'.
-type filename()  :: string().

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
    Res = try
              collect_remote_info(Node, Opts, FH)
          catch X:Y ->
                  io:format("Error: ~P ~P at ~p\n",
                            [X, 20, Y, 20, erlang:get_stacktrace()]),
                  error
          after
              catch file:close(FH)
          end,
    Res.

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
    io:format(FH, "<h1>Node Reports</h1>\n", []),
    io:format(FH, "<ul>\n", []),
    [io:format(FH,"<li> <a href=\"#~p\">~p</a>\n", [Node, Node]) ||
        Node <- Nodes],
    io:format(FH, "</ul>\n\n", []),
    file:close(FH),

    Res = [dump_node(Node, Path, Opts) || Node <- Nodes],
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

format(FH, Fmt) ->
    format(FH, Fmt, []).

format(FH, Fmt, Args) ->
    io:format(FH, Fmt, Args).

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

collect_remote_info(Node, Opts, FH) ->
    dbg("D: node = ~p\n", [Node]),
    format(FH, "\n"),
    format(FH, "<a name=\"~p\">\n", [Node]),
    format(FH, "<h1>Local node cluster_info dump, Node: ~p</h1>\n", [Node]),
    format(FH, "   Options: ~p\n", [Opts]),
    format(FH, "\n"),
    Mods0 = lists:sort([Mod || {Mod, _Path} <- code:all_loaded()]),
    Filters = proplists:get_value(modules, Opts, [all]),
    Mods = [M || M <- Mods0,
                 lists:member(all, Filters) orelse
                     lists:member(M, Filters)],

    [case (catch Mod:cluster_info_generator_funs()) of
         {'EXIT', _} ->
             ok;
         NameFuns when is_list(NameFuns) ->
             format(FH, "<ul>\n", []),
             [begin
                  A = make_anchor(Node, Mod, Name),
                  format(
                    FH, "<li> <a href=\"#~s\">~s</a>\n", [A, Name])
              end || {Name, _} <- NameFuns],
             format(FH, "<ul>\n", []),
             [try
                  dbg("D: generator ~p ~s\n", [Fun, Name]),
                  format(FH, "\n<a name=\"~s\">\n",
                                  [make_anchor(Node, Mod, Name)]),
                  format(FH, "<h2>Report: ~s (~p)</h2>\n\n",
                                  [Name, Node]),
                  format(FH, "<pre>\n", []),
                  RC = fun(M, F, A) ->
                               rpc:call(Node, M, F, A, 10000)
                       end,
                  Fun(FH, RC)
              catch X:Y ->
                      format(FH, "Error in ~p: ~p ~p at ~p\n",
                             [Name, X, Y, erlang:get_stacktrace()])
              after
                  format(FH, "</pre>\n", []),
                  format(FH, "\n")
              end || {Name, Fun} <- NameFuns]
     end || Mod <- Mods],
    ok.

dbg(_Fmt, _Args) ->
   ok.

%% dbg(Fmt, Args) ->
%%     io:format(Fmt, Args).

get_limits() ->
    case erlang:get(?DICT_KEY) of
        undefined ->
            case code:which(riak_err_handler) of
                non_existing ->
                    {undefined, undefined};
                _ ->
                    %% Use factor of 4 because riak_err's settings are
                    %% fairly conservative by default, e.g. 64KB.
                    Apps = [{riak_err, 4}, {cluster_info, 1}],
                    Res = {try_app_envs(Apps, term_max_size, default_size()),
                           try_app_envs(Apps, fmt_max_bytes, default_size())},
                    erlang:put(?DICT_KEY, Res),
                    Res
            end;
        T when is_tuple(T) ->
            T
    end.

reset_limits() -> erlang:erase(?DICT_KEY).

default_size() -> 256*1024.

try_app_envs([{App, Factor}|Apps], Key, Default) ->
    case application:get_env(App, Key) of
        undefined ->
            try_app_envs(Apps, Key, Default);
        {ok, N} ->
            N * Factor
    end;
try_app_envs([], _, Default) ->
    Default.

make_anchor(Node0, Mod, Name) ->
    NameNoSp = re:replace(Name, " ", "",
                          [{return, list}, global]),
    Node = re:replace(atom_to_list(Node0), "'", "", [{return, list}, global]),
    lists:flatten(io_lib:format("~s~w~s",
                                [Node, Mod, NameNoSp])).
