-module(pub).
-compile(export_all).
-include_lib("nitro/include/nitro.hrl").
-behaviour(application).
-export([start/2, stop/1, init/1]).

ext("tex") -> "TeX Source";
ext("htm") -> "HTML";
ext("pdf") -> "PDF";
ext("txt") -> "TXT UTF-8";
ext("dct") -> "TibetDoc".

tbrc_work(A) -> string:to_lower(hd(A)) == $w.

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
                        true  ->  [ { pub, Parent, vers_size(Res), "", ParentParent, "", Res } | Result ];
                        false ->  [ { cat, Parent, "", ParentParent, Res }    | Result ] end;
         false -> case tbrc_work(Parent) of
                      true  -> [ { ver, list_to_atom(Parent), tbrc_files(Path) } | Result ];
                      false -> ScannedFiles = tbrc_files(Path),
                               [ { pub, Parent, print_size(files_size(ScannedFiles)), "", ParentParent, "", Files } | Result ] end end.

print_size(Size) when Size > 1000000000 -> io_lib:format("~.1fG",[Size/1000000000]);
print_size(Size) when Size > 1000000    -> io_lib:format("~.1fM",[Size/1000000]);
print_size(Size) when Size > 1000       -> io_lib:format("~.1fK",[Size/1000]);
print_size(Size) when Size > 0          -> io_lib:format("~.1fB",[Size]);
print_size(Size) -> "0".

files_size(Files) -> lists:sum([ filelib:file_size(F) || F <- Files]).
vers_size(Versions) -> print_size(lists:sum([ files_size(Files) || {ver,_,Files} <- Versions])).

tbrc_size({ver,_,Files}) -> files_size(Files);
tbrc_size({pub,_,_,_,_,_,Files}) -> lists:sum([ F || F <- Files]).
tbrc_files(Path) ->
    [ F || F <- mad_repl:wildcards([lists:concat([Path,"/*.{pdf,PDF}"])]),
                  not filelib:is_dir(F),
                  lists:sum([string:str(filename:basename(F),nitro:to_list(X))||X<-lists:seq(0,9)]) > 0 ].

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


start(_StartType, _StartArgs) -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
stop(_State) -> ok.
init([]) -> {ok, {{one_for_one, 5, 10}, []}}.

tex(Folder,Name) ->
    "\\documentclass[8pt,twoside]{article}\n"
    "\\input{synrc.tex}\n"
    "\\begin{document}\n"
    "\\ru\n"
    "\\subimport{" ++ Folder ++ "/}{\"" ++ Name ++"\"}\n"
    "\\end{document}\n".

tex2(F,Ext) -> filename:basename(F, ".tex") ++ Ext.

main(A) -> 
    ok = io:setopts(standard_io, [{encoding, unicode}]),
    run(A).

to_list('') -> "";
to_list(Atom) when is_atom(Atom) -> atom_to_list(Atom) ++ " ";
to_list(Atom) when is_integer(Atom) -> integer_to_list(Atom) ++ " ";
to_list(L) -> L.

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

output() -> {fun outputCat/3, fun outputPub/3}.
search() -> {fun searchCat/3, fun searchPub/3}.

run([])           -> io:format("PUB nying.ma Publishing System ~n"),
                     io:format("Usage:~n"),
                     io:format("   pub i          -- print index~n"),
                     io:format("   pub d          -- directory scan~n"),
                     io:format("   pub r          -- REPL~n"),
                     io:format("   pub s <text>   -- search in index~n"),
                     io:format("   pub tex <file> -- publish TeX file~n"),
                     io:format("   pub tex        -- publish folder with TeX, DCT, TXT~n"),
                     false;
run(["tex"])      -> publish(mad_repl:wildcards(["*.tex"])), false;
run(["i"])        -> {ok,[L]} = file:consult("index.erl"), fold(0,L,output(),[]), false;
run(["s",String]) -> {ok,[L]} = file:consult("index.erl"), fold(0,lists:flatten(fold(0,L,search(),String)),output(),[]), false;
run(["d"])        -> %io:format("~p~n",[scan(mad_utils:cwd(),[])]), 
                     fold(0,scan(mad_utils:cwd(),[]),output(),[]), false;
run(["r"])        -> mad_repl:main([],[]);
run(["tex",File]) -> publish([File]), false.

ver(Versions) -> string:join(unver(Versions),"").
unver(Versions) -> lists:foldl(fun({ver,Work,Pages},Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                   ({ver,Work,Pages},Acc) when is_list(Work) -> Acc;
                                            (Work,Acc) when is_atom(Work) -> [to_list(Work)|Acc];
                                            (Work,Acc) when is_list(Work) -> Acc;
                                            ({ver,Work,Pages},Acc) when is_list(Work) -> [ver(Work)|Acc] end,[],Versions).

indent(Depth) -> [ io:format("|   ") || _ <- lists:seq(1,Depth) ].

outputCat(Depth,{cat,Name,Desc,Path,List},S) ->
    indent(Depth), io:format("+-- ~s~n",[to_list(Name)]), [].
outputPub(Depth,{pub,Name,Num,Wylie,Path,Desc,Ver},S) ->
    indent(Depth), X = io:format("+-- ~s ~s ~ts ~s~n",[to_list(Name),to_list(Num),%Wylie,
                                                                         wylie:tibetan(Wylie),
                                                                         ver(Ver)]), [].

searchCat(Depth,{cat,Name,Desc,Path,List}=Cat,S) ->
    case lists:sum([string:str(string:to_lower(X),string:to_lower(S))||X<-[to_list(Name),Desc]]) of 0 -> []; N -> [{cat,Name,Desc,Path,[]}] end.
searchPub(Depth,{pub,Name,Num,Wylie,Path,Desc,Ver}=Pub,S) ->
    case lists:sum([string:str(string:to_lower(X),string:to_lower(S))||X<-[to_list(Name),Desc,Wylie]++unver(Ver)]) of 0 -> []; N -> [Pub] end.

fold(Depth,List,{Fun1,Fun2},S) ->
    lists:foldl(fun({cat,_,_,_,L}=Cat,Acc)     -> [Acc|[Fun1(Depth,Cat,S)|fold(Depth+1,L,{Fun1,Fun2},S)]];
                   ({pub,_,_,_,_,_,_}=Pub,Acc) -> [Acc|Fun2(Depth,Pub,S)] end, [], List).
