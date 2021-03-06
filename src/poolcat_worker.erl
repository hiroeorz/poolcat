-module(poolcat_worker).

-behaviour(gen_server).

-callback init(any()) -> {ok, term()}.
-callback handle_pop(term(), State0::term()) -> {ok, State1::term()}.
-callback terminate(term(), term()) -> ok.

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include_lib("eunit/include/eunit.hrl").

-define(SERVER, ?MODULE).

-record(state,
        {
          mod :: atom(),
          state :: term(),
          qname :: atom()
        }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Name,Module,InitData) ->
    gen_server:start_link(?MODULE, [Name,Module,InitData], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([Name,Module,InitData]) ->
    {ok, State} = Module:init(InitData),
    {ok, #state{mod=Module,state=State,qname=Name}, 1}.

%% @private
handle_call(stop, _, State) ->
    {stop, normal, State};
handle_call(_, _From, State) ->
    {reply, error, State, 0}.

%% @private
handle_cast(pause, State) ->
    {noreply, State};
handle_cast(resume, State) ->
    {noreply, State, 0};
handle_cast(_Msg, State) ->
    {noreply, State, 0}.

%% @private
handle_info(timeout, #state{mod=Module,qname=QName,state=SubState0}=State) ->
    case gen_queue:pop(QName) of
        {ok,{task, Task}} ->
            {ok,SubState} = Module:handle_pop(Task,SubState0),
            {noreply, State#state{state=SubState}, 0};
        {ok,{task, Task, TaskID, From}} ->
            Result = Module:handle_pop(Task,SubState0),
            From ! {TaskID, Result},
            case Result of
                {ok, SubState} ->
                    {noreply, State#state{state=SubState}, 0};
                _Other ->
                    {noreply, State, 0}
            end;
        {ok, stop} ->
            {stop, normal, State};
        {ok, {stop, Pid}} ->
            Pid ! {ok, ?MODULE},
            {stop, normal, State};
        {error, destroyed} ->
            {stop, normal, State}
    end.

%% @private
terminate(Reason, #state{mod=Module,state=SubState} = _State) ->
    Module:terminate(Reason, SubState).

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
