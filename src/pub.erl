-module(pub).
-compile(export_all).
-include_lib("nitro/include/nitro.hrl").
-behaviour(application).
-export([start/2, stop/1, init/1]).

% Directory Scan

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

files_size(Files) -> lists:sum([ filelib:file_size(F) || F <- Files]).
vers_size(Versions) -> print_size(lists:sum([ files_size(Files) || {ver,_,Files} <- Versions])).
vers_files(Versions) -> lists:flatten([ [ {ver,A,filename:basename(F)} || F <- Files ] || {ver,A,Files} <- Versions]).
base_files(Files) -> [ filename:basename(F) || F <- Files ].

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

cache()  -> {fun cacheCat/3,  fun cachePub/3}.
merge()  -> {fun mergeCat/3,  fun mergePub/3}.
output() -> {fun outputCat/3, fun outputPub/3}.
search() -> {fun searchCat/3, fun searchPub/3}.

merge(Parameters) ->
    Scan = scan(mad_utils:cwd(),[]),
    fold(0,Scan,cache(),[]),
    {ok,[L]} = file:consult("index.erl"),
    lists:flatten(mergeFold(0,lists:reverse(L),merge(),Parameters)).

run([])           -> io:format("Digital Library Publishing System ~n"),
                     io:format("Copyright (c) Longchen Nyingthig Ukraine ~n"),
                     io:format("~n"),
                     io:format("Usage:~n"),
                     io:format("       pub i          -- print TBRC index~n"),
                     io:format("       pub dump       -- dump Erlang merged scan/index~n"),
                     io:format("       pub s          -- display everything, actual with sizes~n"),
                     io:format("       pub u          -- not synced, show 'to download' list~n"),
                     io:format("       pub d          -- available on disk (directory scan)~n"),
                     io:format("       pub repl       -- REPL~n"),
                     io:format("       pub f <text>   -- search in index~n"),
                     io:format("       pub tex <file> -- publish TeX file~n"),
                     io:format("       pub tex        -- publish folder with TeX, DCT, TXT~n"),
                     false;
run(["tex"])      -> publish(mad_repl:wildcards(["*.tex"])), false;
run(["i"])        -> {ok,[L]} = file:consult("index.erl"), fold(0,L,output(),[]), false;
run(["u"]=P)      -> fold(0,merge(["s"]),output(),P), false;
run(["s"]=P)      -> fold(0,merge(["s"]),output(),P), false;
run(["fu",S])     -> fold(0,lists:flatten(fold(0,merge(["u"]),search(),S)),output(),["u"]), false;
run(["fs",S])     -> fold(0,lists:flatten(fold(0,merge(["s"]),search(),S)),output(),[]), false;
run(["fi",S])     -> {ok,[L]} = file:consult("index.erl"),
                     fold(0,lists:flatten(fold(0,L,search(),S)),output(),[]), false;
run(["dump"])     -> io:format("~p~n",[scan(mad_utils:cwd(),[])]), false;
run(["d"])        -> {ok,[L]} = file:consult("index.erl"),
                     fold(0,L,cache(),[]),
                     Merged = mergeFold(0,scan(mad_utils:cwd(),[]),merge(),[]),
                     fold(0,lists:flatten(Merged),output(),[]),
                     false;
run(["fd",S])     -> {ok,[L]} = file:consult("index.erl"),
                     fold(0,L,cache(),[]),
                     Merged = mergeFold(0,scan(mad_utils:cwd(),[]),merge(),[]),
                     fold(0,fold(0,lists:flatten(Merged),search(),S),output(),[]),
                     false;
run(["repl"])     -> mad_repl:main([],[]);
run(["tex",File]) -> publish([File]), false.

ver(Versions)     -> string:join(unver(Versions),"").
unver(Versions)   -> lists:foldl(fun ({ver,Work,_},Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                     ({ver,Work,_},Acc) when is_list(Work) -> [ver(Work)|Acc];
                                             (Work,Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                             (Work,Acc) when is_list(Work) -> Acc end,[],Versions).

indent(Depth) -> [ io:format("|   ") || _ <- lists:seq(1,Depth) ].

lookup(Key) ->
    Res = ets:lookup(fs,Key),
    case Res of
         [] -> undefined;
         [Value] -> Value;
         Values -> Values end.

cacheCat(_,{cat,Name,_,_,_}=Cat,_)     -> ets:insert(fs,setelement(2,Cat,Name)).
cachePub(_,{pub,Name,_,_,_,_,_}=Pub,_) -> ets:insert(fs,setelement(2,Pub,atom_to_list(Name))).

mergeCat(Depth,{cat,Name,_,_,_}=Cat,P) -> Cat.
mergePub(Depth,{pub,Name,SizeNum,Wylie,_Path,_Desc,Ver}=Pub,Parameters) ->
    Cache = lookup(atom_to_list(Name)),
    case Cache of
         undefined -> Pub;
                 _ -> case element(3,Cache) of
                           {_,_} -> setelement(3,Pub,element(3,Cache));
                               _ -> setelement(3,Cache,element(3,Pub)) end end.

outputCat(Depth,{cat,Name,_Desc,_Path,_List},_) ->
    indent(Depth),
    io:format("+-- ~s~n",[to_list(Name)]), [].
outputPub(Depth,{pub,Name,SizeNum,Wylie,_Path,_Desc,Ver}=Pub,Parameters) ->
    case SizeNum of
         {Size,Num} -> case Parameters of
                            ["u"] -> skip;
                                _ -> indent(Depth),
                                     io:format("+-- ~s ~w:[~s] ~ts ~s~n",
                                     [Name,Num,to_list(Size),wylie:tibetan(Wylie),ver(Ver)]), [] end;
              Num   -> indent(Depth),
                       io:format("+-- ~s ~w ~ts ~s~n",
                       [Name,Num,wylie:tibetan(Wylie),ver(Ver)]), [] end.

lower(X) -> string:to_lower(X).
has(X,Y) -> string:str(X,Y).

searchCat(_,{cat,Name,Desc,Path,_List},S) ->
    case lists:sum([has(lower(X),lower(S))||X<-[to_list(Name),Desc]]) of
         0 -> [];
         _ -> [{cat,Name,Desc,Path,[]}] end.
searchPub(_,{pub,Name,_Num,Wylie,_Path,Desc,Ver}=Pub,S) when is_integer(_Num) andalso S == ["u"] -> [];
searchPub(_,{pub,Name,_Num,Wylie,_Path,Desc,Ver}=Pub,S) ->
    case lists:sum([has(lower(X),lower(S))||X<-[to_list(Name),Desc,Wylie]++unver(Ver)]) of
         0 -> [];
         _ -> [Pub] end.

fold(Depth,List,{Fun1,Fun2},S) ->
    lists:foldl(fun({cat,_,_,_,L}=Cat,Acc)     -> lists:flatten([[Fun1(Depth,Cat,S)|fold(Depth+1,L,{Fun1,Fun2},S)]|Acc]);
                   ({ver,_,_},Acc)             -> Acc;
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [Fun2(Depth,Pub,S)|Acc] end, [], List).

mergeFold(Depth,List,{Fun1,Fun2},S) ->
    lists:foldl(fun({cat,N,D,P,L}=Cat,Acc)     -> [Fun1(Depth,{cat,N,D,P,mergeFold(Depth,lists:reverse(L),{Fun1,Fun2},S)},S)|Acc];
                   ({ver,_,_},Acc)             -> Acc;
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [Fun2(Depth,Pub,S)|Acc] end, [], List).
