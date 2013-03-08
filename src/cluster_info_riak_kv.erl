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

-module(cluster_info_riak_kv).
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
     {"Riak KV status", fun status/2},
     {"Riak KV ringready", fun ringready/2},
     {"Riak KV transfers", fun transfers/2}
    ].

status(C, RC) -> 
    cluster_info:format(C, "~p\n", [RC(riak_kv_status, statistics, [])]).

ringready(C, RC) ->
    cluster_info:format(C, "~p\n", [RC(riak_kv_status, ringready, [])]).

transfers(C, RC) ->
    cluster_info:format(C, "~p\n", [RC(riak_kv_status, transfers, [])]).

