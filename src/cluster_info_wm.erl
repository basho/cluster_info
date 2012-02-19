-module(cluster_info_wm).

-export([init/1,
         malformed_request/2,
         content_types_provided/2,
         %% encodings_provided/2,
         to_text/2]).

-include_lib("webmachine/include/webmachine.hrl").

-define(CHUNK_SIZE, 32768).

-record(state, {temp :: string(),
                nodes=[] :: list(string()) | atom}).

init([]) ->
    Temp = case application:get_env(cluster_info, temp_dir) of
               undefined ->
                   os:getenv("TMPDIR");
               {ok, Dir} -> Dir
           end,
    {ok, #state{temp = Temp}}.

malformed_request(RD, State) ->
    KnownNodes = [ atom_to_list(N) || N <- [node()|nodes()] ],
    {RequestedNodes, RD1} = case proplists:get_all_values("node", wrq:req_qs(RD)) of
                                [] ->
                                    {local, RD};
                                ["all"] ->
                                    {all, RD};
                                List ->
                                    {Known, Unknown} = lists:partition(fun(N) -> lists:member(N, KnownNodes) end, List),
                                    case length(Unknown) of
                                        0 -> {[ list_to_existing_atom(Node) || Node <- Known], RD};
                                        _ ->
                                            {false, wrq:set_resp_header("Content-Type", "text/plain", wrq:set_resp_body(io_lib:format("Unknown nodes: ~p~n", [Unknown]), RD))}
                                    end
                            end,
    {RequestedNodes =:= false, RD1, State#state{nodes=RequestedNodes}}.


content_types_provided(RD, State) ->
    {[{"text/plain", to_text}], RD, State}.

to_text(RD, State=#state{temp = Temp, nodes=Nodes}) ->
    Filename = filename:join([Temp, integer_to_list(erlang:phash2([RD, self()]))]),
    dump(Nodes, Filename),
    {ok, Handle} = file:open(Filename, [read, read_ahead, binary]),
    {{stream, stream_file(Handle, Filename)}, RD, State}.

stream_file(Handle, File) ->
    case file:read(Handle, ?CHUNK_SIZE) of
        eof ->
            file:close(Handle),
            file:delete(File),
            {<<>>, done};
        {ok, Data} ->
            {Data, fun() -> stream_file(Handle, File) end}
    end.

dump(local, Filename) ->
    cluster_info:dump_local_node(Filename);
dump(all, Filename) ->
    cluster_info:dump_all_connected(Filename);
dump(Nodes, Filename) ->
    cluster_info:dump_nodes(Nodes, Filename).
