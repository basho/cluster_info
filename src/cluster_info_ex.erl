%%%----------------------------------------------------------------------
%%% Copyright: (c) 2009-2010 Gemini Mobile Technologies, Inc.  All rights reserved.
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
%%% File    : cluster_info_ex.erl
%%% Purpose : cluster info example
%%%----------------------------------------------------------------------

-module(cluster_info_ex).

-export([cluster_info_init/0, cluster_info_generator_funs/0]).

%% @spec () -> term()
%% @doc Required callback function for cluster_info: initialization.
%%
%% This function doesn't have to do anything.

cluster_info_init() ->
    ok.

%% @spec () -> list({string(), fun()})
%% @doc Required callback function for cluster_info: return list of
%%      {NameForReport, FunOfArity_1} tuples to generate ASCII/UTF-8
%%      formatted reports.

cluster_info_generator_funs() ->
    [
     {"Simple first example", fun example_1/1},
     {"Only slightly more complex example", fun example_2/1}
    ].

example_1(CPid) -> % CPid is the data collector's pid.
    cluster_info:format(CPid, "Hello, world!\n").

example_2(CPid) ->
    cluster_info:send(
      CPid, ["Here is some sample data:\n",
             <<"The quick brown fox...\n\n">>]),
    cluster_info:format(CPid, "Output from 'ls -l':\n\n"),
    cluster_info:send(CPid, os:cmd("ls -l")).
