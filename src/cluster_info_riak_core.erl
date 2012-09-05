%% -------------------------------------------------------------------
%%
%% Riak: A lightweight, decentralized key-value store.
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
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
-module(cluster_info_riak_core).

-export([cluster_info_init/0, cluster_info_generator_funs/0]).

%% @spec () -> term()
%% @doc Required callback function for cluster_info: initialization.
%%
%% This function doesn't have to do anything.

cluster_info_init() ->
    ok.

%% @spec () -> list({string(), fun()})
%% @doc Required callback function for cluster_info: return list of
%%      {NameForReport, FunOfArity_2} tuples to generate ASCII/UTF-8
%%      formatted reports.

cluster_info_generator_funs() ->
    [
     {"Riak Core config files", fun config_files/2},
     {"Riak Core vnode modules", fun vnode_modules/2},
     {"Riak Core ring", fun get_my_ring/2},
     {"Riak Core latest ring file", fun latest_ringfile/2},
     {"Riak Core active partitions", fun active_partitions/2}
    ].

vnode_modules(C, RC) -> % C, RC is the data collector's pid.
    cluster_info:format(C, "~p\n", [RC(riak_core, vnode_modules, [])]).

get_my_ring(C, RC) ->
    {ok, Ring} = RC(riak_core_ring_manager, get_my_ring, []),
    cluster_info:format(C, "~p\n", [Ring]).

latest_ringfile(C, RC) ->
    {ok, Path} = RC(riak_core_ring_manager, find_latest_ringfile, []),
    {ok, Contents} = RC(file, read_file, [Path]),
    cluster_info:format(C, "Latest ringfile: ~s\n", [Path]),
    cluster_info:format(C, "File contents:\n~p\n", [binary_to_term(Contents)]).

active_partitions(C, RC) ->
    Pids = [Pid || {_,Pid,_,_} <- RC(supervisor, which_children, [riak_core_vnode_sup])],
    Vnodes = [RC(riak_core_vnode, get_mod_index, [Pid]) || Pid <- Pids],
    Partitions = lists:foldl(fun({_,P}, Ps) -> 
                                     ordsets:add_element(P, Ps)
                             end, ordsets:new(), Vnodes),
    cluster_info:format(C, RC, "~p\n", [Partitions]).

config_files(C, RC) ->
    {ok, [[AppPath]]} = RC(init, get_argument, [config]),
    EtcDir = filename:dirname(AppPath),
    VmPath = filename:join(EtcDir, "vm.args"),
    [begin
         cluster_info:format(C, "File: ~s\n", [RC(os, cmd, ["ls -l " ++ File])]),
         {ok, FileBin} = RC(file, read_file, [File]),
         cluster_info:format(C, "File contents:\n~s\n", [FileBin])
     end || File <- [AppPath, VmPath]].

