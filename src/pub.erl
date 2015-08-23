-module(pub).
-compile(export_all).
-include_lib("nitro/include/nitro.hrl").
-behaviour(application).
-export([start/2, stop/1, init/1]).

% Merge

merge(Parameters) ->
    Scan = scan(mad_utils:cwd(),[]),
    fold(0,Scan,cache(),[]),
    lists:flatten(mergeFold(0,lists:reverse(index()),merge(),Parameters)).

% Index

index() ->
    case file:consult("index.erl") of
         {ok,[L]} -> lists:reverse(path([],L,[]));
                _ -> lists:reverse(path([],index:meta(),[])) end.

% Directory Scan

scan() -> scan(mad_utils:cwd(),[]).
scan(Path,Result) ->
    Components   = string:tokens(Path,"/"),
    Wildcard     = lists:concat([Path,"/*"]),
    Files        = mad_repl:wildcards([Wildcard]),
    Parent       = hd(lists:reverse(Components)),
    ParentParent = hd(tl(lists:reverse(Components))),
    {OnlyDirs,HasPub} = lists:foldl(fun(A,{F,P}) ->
                {F andalso filelib:is_dir(A), P orelse filename:basename(A) == "pub"} end,
                {true,false},Files),
    case (OnlyDirs orelse HasPub) of
         true  -> Res = lists:flatten([ scan(lists:concat([Path,"/",filename:basename(F)]),[]) || F <- Files, filelib:is_dir(F) ]),
                   case lists:all(fun({ver,_,_}) -> true;
                                     (_) -> false end, Res) of
                        true  ->  VerFiles = Res,%vers_files(Res),
                                  [ { pub, list_to_atom(Parent), {vers_size(Res),length(VerFiles)}, "", ParentParent, "", VerFiles } | Result ];
                        false ->  [ { cat, Parent, "", ParentParent, Res }    | Result ] end;
         false -> case tbrc_work(Parent) of
                      true  -> [ { ver, list_to_atom(Parent), tbrc_files(Path) } | Result ];
                      false -> ScannedFiles = tbrc_files(Path),
                               [ { pub, list_to_atom(Parent), {print_size(files_size(ScannedFiles)),length(ScannedFiles)}, "", ParentParent, "", base_files(ScannedFiles) } | Result ] end end.

print_size(Size) when Size > 1000000000 -> io_lib:format("~.1fG",[Size/1000000000]);
print_size(Size) when Size > 1000000    -> io_lib:format("~.1fM",[Size/1000000]);
print_size(Size) when Size > 1000       -> io_lib:format("~.1fK",[Size/1000]);
print_size(Size) when Size > 0          -> io_lib:format("~.1fB",[Size]);
print_size(_Size) -> "_".

files_size(Files)    -> lists:sum([ filelib:file_size(F) || F <- Files]).
vers_size(Versions)  -> print_size(lists:sum([ files_size(Files) || {ver,_,Files} <- Versions])).
vers_files(Versions) -> lists:flatten([ [ {ver,A,filename:basename(F)} || F <- Files ] || {ver,A,Files} <- Versions]).
base_files(Files)    -> [ filename:basename(F) || F <- Files ].

tbrc_work(A) -> string:to_lower(hd(A)) == $w.
tbrc_size({ver,_,Files}) -> files_size(Files);
tbrc_size({pub,_,_,_,_,_,Files}) -> lists:sum([ F || F <- Files]).
tbrc_files(Path) ->
    [ F || F <- mad_repl:wildcards([lists:concat([Path,"/*.{pdf,PDF}"])]),
                  not filelib:is_dir(F),
                  lists:sum([string:str(filename:basename(F),nitro:to_list(X))||X<-lists:seq(0,9)]) > 0 ].

% TeX publication

ext("tex") -> "TeX Source";
ext("htm") -> "HTML";
ext("pdf") -> "PDF";
ext("txt") -> "TXT UTF-8";
ext("dct") -> "TibetDoc".

menu(File,Author) ->
   Files = mad_repl:wildcards([tex2(File,".{htm,pdf,txt,dct}")]),
   #panel{id=navcontainer,
          style="margin-top:-8px;margin-left:-8px;margin-right:-8px;border-bottom:1px solid;",
          body=[#ul{id=nav,
                   body=[#li{body=[#link{href="#",body="Navigation"},
                                   #ul{body=[#li{body=#link{href="../../../index.htm",body="Nyingma"}},
                                             #li{body=#link{href="../../../ka.thog/index.htm",body="Kathog"}},
                                             #li{body=#link{href="../index.htm",body="Nyingthig Tsapod"}}]}]},
                         #li{body=[#link{href="#",body="Download"},
                                   #ul{body=
                                   [ #li{body=#link{href=F,
                                         body=ext(tl(filename:extension(F)))}}|| F <- Files ] }]},
                         #li{body=[#link{href="#",body="Translations"},
                                   #ul{body=[ #li{body=#link{href="#",body=Author}}]}]}
                    ]},
                #panel{style="clear:both;"}]}.

tex(Folder,Name) ->
    "\\documentclass[8pt,twoside]{article}\n"
    "\\input{synrc.tex}\n"
    "\\begin{document}\n"
    "\\ru\n"
    "\\subimport{" ++ Folder ++ "/}{\"" ++ Name ++"\"}\n"
    "\\end{document}\n".

tex2(F,Ext) -> filename:basename(F, ".tex") ++ Ext.

publish(Files) ->
    io:format("Current Directory: ~p~n",[mad_utils:cwd()]),
    [ begin
        Tex = tex(".",File),
        {_,Status,X} = sh:run("cat \""++ File ++ "\" | grep \"nyingma_author\""),
        Author = case Status of
                  0 -> [_,Translator,_] = string:tokens(nitro:to_list(X),"="), Translator;
                  _ -> "Unknown Translator" end,
        io:format("Status ~p Author: ~p~n",[Status, Author]),
        file:write_file("head.htx",nitro:render(menu(File,Author))),
        io:format("Processing: ~p~n",[File]),
        file:write_file("temp.tex",Tex),
        sh:run("xelatex --interaction nonstopmode \"temp.tex\""),
        sh:run("hevea \""++ File ++"\" -o \"" ++ tex2(File,".htm") ++ "\""),
        file:rename("temp.pdf",tex2(File,".pdf"))
      end || File <- Files, File /= "synrc.tex", File /= "temp.tex"].

% Main

start(_StartType, _StartArgs) -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
stop(_State) -> ok.
init([]) -> {ok, {{one_for_one, 5, 10}, []}}.
mnesia() -> ets:new(fs,[set,named_table,{keypos,2},public]).
main(A) -> mnesia(), io:setopts(standard_io, [{encoding, unicode}]), run(A).

to_list('') -> "";
to_list(Atom) when is_atom(Atom) -> atom_to_list(Atom) ++ " ";
to_list(Atom) when is_integer(Atom) -> integer_to_list(Atom) ++ " ";
to_list(L) -> L.

% Command Line Processor

run([])           -> io:format("PUB Tibetan Digital Library Publishing System ~n"),
                     io:format("Copyright (c) Longchen Nyingthig Ukraine ~n"),
                     io:format("~n"),
                     io:format("Usage:~n"),
                     io:format("       pub i          -- print meta index~n"),
                     io:format("       pub s          -- meta index with sizes for available volumes~n"),
                     io:format("       pub d          -- show only available volumes (filesystem tree output)~n"),
                     io:format("       pub u          -- show only unavailable volumes that should be downloaded~n"),
                     io:format("       pub f <text>   -- search in everything~n"),
                     io:format("       pub fd <text>  -- search in available~n"),
                     io:format("       pub dump       -- dump meta index in Erlang format~n"),
                     io:format("       pub repl       -- REPL~n"),
                     io:format("       pub tex <file> -- publish TeX file~n"),
                     io:format("       pub tex        -- publish folder with TeX, PDF, TibetDoc, TXT files~n"),
                     false;
run(["i"|_])      -> fold(0,index(),     output(),[]),    false;
run(["u"|_])      -> fold(0,merge(["u"]),output(),["u"]), false;
run(["s"|_])      -> fold(0,merge(["s"]),output(),[]),    false;
run(["d"])        -> fold(0,index(),cache(),[]), fold(0,mergeFold(0,scan(),merge(),[]),output(),[]), false;
run(["fi",S])     -> fold(0,fold(0,index(),      search(),S),output(),[]),    false;
run(["fu",S])     -> fold(0,fold(0,merge(["u"]), search(),S),output(),["u"]), false;
run(["f",S])      -> fold(0,fold(0,merge(["s"]), search(),S),output(),[]),    false;
run(["fd",S])     -> fold(0,index(),cache(),[]), fold(0,fold(0,mergeFold(0,scan(),merge(),[]),search(),S),output(),[]), false;
run(["repl"])     -> mad_repl:main([],[]);
run(["dump"])     -> io:format("~p~n",[scan(mad_utils:cwd(),[])]), false;
run(["tex"])      -> publish(mad_repl:wildcards(["*.tex"])), false;
run(["tex",File]) -> publish([File]), false.

% Cache Combinators

cache()  -> {fun cacheCat/3,  fun cachePub/3}.
cacheCat(_,{cat,Name,_,_,_}=Cat,_)     -> ets:insert(fs,setelement(2,Cat,Name)).
cachePub(_,{pub,Name,_,_,_,_,_}=Pub,_) -> ets:insert(fs,setelement(2,Pub,atom_to_list(Name))).

% Merge Combinators

merge()  -> {fun mergeCat/3,  fun mergePub/3}.
lookup(Key) ->
    Res = ets:lookup(fs,Key),
    case Res of
         [] -> undefined;
         [Value] -> Value;
         Values -> Values end.

mergeCat(_,{cat,_Name,_,_,_}=Cat,_) -> Cat.
mergePub(_,{pub,Name,_SizeNum,_Wylie,_Path,_Desc,_Ver}=Pub,_Parameters) ->
    Cache = lookup(atom_to_list(Name)),
    case Cache of
         undefined -> Pub;
                 _ -> case element(3,Cache) of
                           {_,_} -> setelement(3,Pub,element(3,Cache));
                               _ -> setelement(3,Cache,element(3,Pub)) end end.

% Output Fold Combinators

output() -> {fun outputCat/3, fun outputPub/3}.
indent(Depth) -> [ io:format("|   ") || _ <- lists:seq(1,Depth) ].
ver(Versions) -> string:join(unver(Versions),"").

outputCat(Depth,{cat,Name,_Desc,_Path,_List},_) ->
    indent(Depth),
    io:format("+-- ~s~n",[to_list(Name)]), [].
outputPub(Depth,{pub,Name,SizeNum,Wylie,_Path,_Desc,Ver},Parameters) ->
    case SizeNum of
         {Size,Num} -> case Parameters of
                            ["u"] -> skip;
                                _ -> indent(Depth),
                                     io:format("+-- ~s ~w:[~s] ~ts ~s~n",
                                     [Name,Num,to_list(Size),wylie:tibetan(Wylie),ver(Ver)]), [] end;
              Num   -> indent(Depth),
                       io:format("+-- ~s ~w ~ts ~s~n",
                       [Name,Num,wylie:tibetan(Wylie),ver(Ver)]), [] end.

% Seacrh Fold Combinators

search() -> {fun searchCat/3, fun searchPub/3}.
lower(X) -> string:to_lower(X).
has(X,Y) -> string:str(X,Y).
unver(Versions) -> lists:foldl(fun ({ver,Work,_},Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                   ({ver,Work,_},Acc) when is_list(Work) -> [ver(Work)|Acc];
                                           (Work,Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                           (Work,Acc) when is_list(Work) -> Acc end,[],Versions).

searchCat(_,{cat,Name,Desc,Path,_List},S) ->
    case lists:sum([has(lower(X),lower(S))||X<-[to_list(Name),Desc]]) of
         0 -> [];
         _ -> [{cat,Name,Desc,Path,[]}] end.
searchPub(_,{pub,_Name,_Num,_Wylie,_Path,_Desc,_Ver},S) when is_integer(_Num) andalso S == ["u"] -> [];
searchPub(_,{pub,Name,_Num,Wylie,Path,Desc,Ver}=Pub,S) ->
    case lists:sum([has(lower(X),lower(S))||X<-[to_list(Name),Desc,Wylie,Path]++unver(Ver)]) of
         0 -> [];
         _ -> [Pub] end.

% Known Folds

fold(Depth,List,{Fun1,Fun2},S) ->
    lists:foldl(fun({cat,_,_,_,L}=Cat,Acc)     -> lists:flatten([[Fun1(Depth,Cat,S)|fold(Depth+1,L,{Fun1,Fun2},S)]|Acc]);
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [Fun2(Depth,Pub,S)|Acc];
                                       (_,Acc) -> Acc end, [], List).

mergeFold(Dep,List,{Fun1,Fun2},S) ->
    lists:foldl(fun({cat,N,D,P,L},Acc)         -> [Fun1(Dep,{cat,N,D,P,mergeFold(Dep,lists:reverse(L),{Fun1,Fun2},S)},S)|Acc];
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [Fun2(Dep,Pub,S)|Acc];
                                       (_,Acc) -> Acc end, [], List).

path(Dep,List,_) ->
    lists:foldl(fun({cat,N,D,P,L},Acc)         -> [{cat,N,D,P,path([N|Dep],lists:reverse(L),Acc)}|Acc];
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [setelement(5,Pub,hd(Dep))|Acc];
                                       (_,Acc) -> Acc end, [], List).
