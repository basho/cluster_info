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
%%%----------------------------------------------------------------------

-module(cluster_info_basic).

%% Registration API
-export([register/0]).

%% Mandatory callbacks.
-export([cluster_info_init/0, cluster_info_generator_funs/0]).

%% Export in case anyone else thinks they might be useful.
-export([alarm_info/2, application_info/2,
         ets_info/2, net_kernel_info/2, nodes_info/2, registered_procs_info/2,
         erlang_memory/2, erlang_statistics/2,
         erlang_system_info/2, global_summary/2, inet_db_summary/2,
         loaded_modules/2, memory_hogs/3, non_zero_mailboxes/2, port_info/2,
         registered_names/2, time_and_date/2, timer_status/2]).

register() ->
    cluster_info:register_app(?MODULE).

cluster_info_init() ->
    ok.

cluster_info_generator_funs() ->
    [
     %% Short(er) output items at the top
     {"Current time and date", fun time_and_date/2},
     {"VM statistics", fun erlang_statistics/2},
     {"erlang:memory() summary", fun erlang_memory/2},
     {"Top 50 process memory hogs", fun(C, RC) -> memory_hogs(C, RC, 50) end},
     {"Non-zero mailbox sizes", fun non_zero_mailboxes/2},
     {"Suspicious link and monitor counts", fun suspicious_links_monitors/2},
     {"Registered process names", fun registered_names/2},
     {"Process info for registered process names", fun registered_procs_info/2},
     {"Ports", fun port_info/2},
     {"Applications", fun application_info/2},
     {"Timer status", fun timer_status/2},
     {"ETS summary", fun ets_info/2},
     {"Nodes summary", fun nodes_info/2},
     {"net_kernel ports information", fun net_kernel_info/2},
     {"inet_db summary", fun inet_db_summary/2},
     {"Alarm summary", fun alarm_info/2},
     {"Global summary", fun global_summary/2},

     %% Longer output starts here.
     {"erlang:system_info() summary", fun erlang_system_info/2},
     {"Loaded modules", fun loaded_modules/2}
    ].

alarm_info(C, RC) ->
    Alarms = RC(alarm_handler, get_alarms, []),
    cluster_info:format(C, " Number of alarms: ~p\n", [length(Alarms)]),
    cluster_info:format(C, " ~p\n", [Alarms]).

application_info(C, RC) ->
    cluster_info:format(C, " Application summary:\n"),
    cluster_info:format(C, " ~p\n", [RC(application, info, [])]),
    [try
         cluster_info:format(C, " Application:get_all_key(~p):\n", [App]),
         cluster_info:format(C, " ~p\n\n", [RC(application, get_all_key, [App])]),
         cluster_info:format(C, " Application:get_all_env(~p):\n", [App]),
         cluster_info:format(C, " ~p\n\n", [RC(application, get_all_env, [App])])
     catch X:Y ->
             cluster_info:format(C, "Error for ~p: ~p ~p at ~p\n",
                                 [App, X, Y, erlang:get_stacktrace()])
     end || App <- lists:sort([A || {A, _, _} <- RC(application, which_applications, [])])].

ets_info(C, RC) ->
    TableList = RC(ets, all, []),
    [cluster_info:format(C, "~w~n", [{Table, RC(ets, info, [Table])}]) || Table <- TableList ].

net_kernel_info(C, RC) ->
    Nodes = [RC(net_kernel, nodes_info, [])],
    cluster_info:format(C, "~w~n", [Nodes]).

registered_procs_info(C, RC) ->
    Regs = RC(erlang, registered, []),
    cluster_info:format(C, "~w~n", [Regs]),
    [cluster_info:format(C, "~w~n", [RC(erlang, process_info, [RC(erlang, whereis, [Proc])])]) ||
                                    Proc <- Regs].

erlang_memory(C, RC) ->
    cluster_info:format(C, " Native report:\n\n"),
    cluster_info:format(C, " ~p\n\n", [RC(erlang, memory, [])]),
    cluster_info:format(C, " Report sorted by memory usage:\n\n"),
    SortFun = fun({_, X}, {_, Y}) -> X > Y end,
    cluster_info:format(C, " ~p\n", [lists:sort(SortFun, RC(erlang, memory, []))]).

erlang_statistics(C, RC) ->
    [cluster_info:format(C, " ~p: ~p\n", [Type, catch RC(erlang, statistics, [Type])])
     || Type <- [context_switches, exact_reductions, garbage_collection,
                 io, reductions, run_queue, runtime, wall_clock]].

erlang_system_info(C, RC) ->
    Allocs = RC(erlang, system_info, [alloc_util_allocators]),
    I0 = lists:flatten(
             [allocated_areas, allocator,
              [{allocator, Alloc} || Alloc <- Allocs],
              [{allocator_sizes, Alloc} || Alloc <- Allocs],
              c_compiler_used, check_io, compat_rel, cpu_topology,
              [{cpu_topology, X} || X <- [defined, detected]],
              creation, debug_compiled, dist_ctrl,
              driver_version, elib_malloc, fullsweep_after,
              garbage_collection, global_heaps_size, heap_sizes,
              heap_type, kernel_poll,
              logical_processors, machine, modified_timing_level,
              multi_scheduling, multi_scheduling_blockers,
              otp_release, process_count, process_limit,
              scheduler_bind_type, scheduler_bindings,
              scheduler_id, schedulers, schedulers_online,
              smp_support, system_version, system_architecture,
              threads, thread_pool_size, trace_control_word,
              version, wordsize]),
    [cluster_info:format(C, " ~p:\n ~p\n\n", [I,catch RC(erlang, system_info, [I])]) ||
        I <- I0],

    I1 = [dist, info, loaded, procs],
    [cluster_info:format(C, " ~p:\n ~s\n\n", [I, catch RC(erlang, system_info, [I])]) ||
        I <- I1].

global_summary(C, RC) ->
    cluster_info:format(C, " info: ~p\n", [RC(global, info, [])]),
    cluster_info:format(C, " registered_names:\n"),
    [try
         Pid = RC(global, whereis_name, [Name]),
         cluster_info:format(C, "    Name ~p, pid ~p, node ~p\n",
                             [Name, Pid, RC(erlang, node, [Pid])])
     catch _:_ ->
             ok
     end || Name <- RC(global, registered_names, [])],
    ok.

inet_db_summary(C, RC) ->
    cluster_info:format(C, " gethostname: ~p\n", [RC(inet_db, gethostname, [])]),
    cluster_info:format(C, " get_rc: ~p\n", [RC(inet_db, get_rc, [])]).

loaded_modules(C, RC) ->
    cluster_info:format(C, " Root dir: ~p\n\n", [RC(code, root_dir, [])]),
    cluster_info:format(C, " Lib dir: ~p\n\n", [RC(code, lib_dir, [])]),
    %% io:format() output only {sniff!}
    %% cluster_info:format(C, " Clashes: ~p\n\n", [code:clash()]),
    PatchDirs = [Dir || Dir <- RC(code, get_path, []), string:str(Dir, "patch") /= 0],
    lists:foreach(
      fun(Dir) ->
              cluster_info:format(C, " Patch dir ~p:\n~s\n\n",
                                  [Dir, RC(os, cmd, ["ls -l " ++ Dir])])
      end, PatchDirs),
    cluster_info:format(C, " All Paths:\n ~p\n\n", [RC(code, get_path, [])]),
    [try
         cluster_info:format(C, " Module ~p:\n", [Mod]),
         cluster_info:format(C, " ~p\n\n", [RC(Mod, module_info, [])])
     catch X:Y ->
             cluster_info:format(C, "Error for ~p: ~p ~p at ~p\n",
                                 [Mod, X, Y, erlang:get_stacktrace()])
     end || Mod <- lists:sort([M || {M, _} <- RC(code, all_loaded, [])])].

memory_hogs(C, RC, Num) ->
    L = lists:sort([{Mem, Pid}
                    || Pid <- RC(erlang, processes, []),
                       {memory, Mem} <- [catch RC(erlang, process_info, [Pid, memory])],
                       is_integer(Mem)]),
    cluster_info:format(C, " ~p\n", [lists:sublist(lists:reverse(L), Num)]).

nodes_info(C, RC) ->
    cluster_info:format(C, " My node: ~p\n", [RC(erlang, node, [])]),
    cluster_info:format(C, " Other nodes: ~p\n", [lists:sort(RC(erlang, nodes, []))]).

non_zero_mailboxes(C, RC) ->
    L = lists:sort([{Size, Pid}
                    || Pid <- RC(erlang, processes, []),
                       {message_queue_len, Size} <-
                           [catch process_info(Pid, message_queue_len)],
                       Size > 0]),
    cluster_info:format(C, " ~p\n", [lists:reverse(L)]).

suspicious_links_monitors(C, RC) ->
    Min = 1000,
    cluster_info:format(C, " Minimum threshold = ~p\n\n", [Min]),
    [begin
         L = lists:sort([{Num, Pid} ||
                            Pid <- RC(erlang, processes, []), 
                            [{_, Mon}] <- [RC(erlang, process_info, [Pid, [Type]])],
                            Num <- [length(Mon)],
                            Num >= Min]),
         cluster_info:format(C, " Type: ~p\n\n", [Type]),
         cluster_info:format(C, "    ~p\n\n", [L])
     end || Type <- [links, monitors]].

port_info(C, RC) ->
    L = [{Port, RC(erlang, port_info, [Port])} || Port <- RC(erlang, ports, [])],
    cluster_info:format(C, " ~p\n", [L]).

registered_names(C, RC) ->
    L = lists:sort([{Name, catch whereis(Name)} || Name <- RC(erlang, registered, [])]),
    cluster_info:format(C, " ~p\n", [L]).

time_and_date(C, RC) ->
    cluster_info:format(C, " Current date: ~p\n", [RC(erlang, date, [])]),
    cluster_info:format(C, " Current time: ~p\n", [RC(erlang, time, [])]),
    cluster_info:format(C, " Current now : ~p\n", [RC(erlang, now, [])]).

timer_status(C, RC) ->
    cluster_info:format(C, " ~p\n", [RC(timer, get_status, [])]).

