module Parser = BuildOCPParser

let read_process command =
  ignore(Unix.system ("echo " ^command));
  let buffer_size = 2048 in
  let buffer = Buffer.create buffer_size in
  let string = String.create buffer_size in
  let in_channel = Unix.open_process_in command in
  let chars_read = ref 1 in
  while !chars_read <> 0 do
    chars_read := input in_channel string 0 buffer_size;
    Buffer.add_substring buffer string 0 !chars_read
  done;
  ignore (Unix.close_process_in in_channel);
  Buffer.contents buffer


let ocp_name = ref "" 
let target = ref "ocp2opam_package"
let version = ref (let open Unix in 
                   let tm = gmtime (gettimeofday ()) in
                   Printf.sprintf "%i%s%i" (1900+ tm.tm_year) 
                     (if tm.tm_mon < 10 then
                        Printf.sprintf "0%i" tm.tm_mon 
                      else
                        string_of_int tm.tm_mon)
                        tm.tm_mday)
    (*(read_process "date +%Y%m%d")*)
let name = ref ""
let url = ref ""

let main () =
  let ocp_arg  = ("-ocp", Arg.String (fun s -> ocp_name := s), 
                  "name of .ocp file in current directory") 
  and target_arg  = ("-target", Arg.String (fun s -> target := s), 
                  "target folder") 

  and url  = ("-url", Arg.String (fun s -> url := s), 
                  "url of repository") 

  in
  Arg.parse [ocp_arg; target_arg] (fun s -> ()) "";
  if !ocp_name = "" then
    (print_endline ("Usage:\n"^
    "-ocp name of .ocp file in currecnt directory\n"^
    "-target target folder\n"^
    "-help  Display this list of options\n"^
    "--help  Display this list of options\n");
     exit 0
    );
  try 
    let ocp_channel =  open_in !ocp_name in
    Printf.printf "Parsing %s\n%!" !ocp_name;
    Printf.printf "Will write into  %s\n%!" !version
  with
  | _ ->
    (Printf.eprintf "%s not found\n%!" !ocp_name;
     exit 1)
;;


main ();;


type package = {
  mutable package_type : string;
  mutable package_name : string;
  mutable requires : BuildOCPTree.string_with_attributes list;
  mutable authors : string list;
  mutable descr: string list;
  mutable license : string list;
}


let run command = 
  ignore(Unix.system ("echo " ^command));
  ignore(Unix.system command)


let get_package package =
  read_process ("ocamlfind list | grep \"^"^package^"[ ]*(\"")

let get_package_version package =
  let base =   get_package package in
  let s =  (Str.split_delim (Str.regexp "  +") base) in
  List.hd (Str.split_delim (Str.regexp ")") (List.nth s (List.length s - 1)))
  

let _ =
  let stmts = 
    BuildOCPParse.read_ocamlconf !ocp_name in
  let authors = ref [] 
  and dirname = ref []
  and descr = ref []
  and packages = ref []
  and requires = ref []
  and license = ref [] in

  let open BuildOCPTree in
  let rec parse_option = function
    | OptionListSet ("dirname" , l) -> 
      dirname := !dirname@l
    | OptionListSet ("authors" , l) -> 
      authors := !authors@l
    | OptionListSet ("descr" , l) -> 
      descr := !descr@l
    | OptionListSet ("license" , l) -> 
      license := !license@l
   | _ -> ()
  and parse_package pt n l = 
    let pkg = {
      package_type = BuildOCPTree.string_of_package_type pt;
      package_name = n;
      requires = [];
      authors = !authors;
      descr = !descr;
      license = !license;      
    } in
    parse_statements (Some pkg )l;
    packages := pkg:: !packages
    
  and parse_statements pkg = function
    | [] -> ()
    | StmtOption l::q -> parse_option l; parse_statements pkg q
    | StmtDefinePackage (pt,n,l) :: q-> parse_package pt n l; parse_statements pkg q
    | StmtRequiresSet l :: q -> 
      ( match pkg with 
        | None -> requires := l 
        | Some pkg -> pkg.requires <- l); parse_statements pkg q
    | t::q -> parse_statements pkg q
  in
  parse_statements None stmts;
  let pwd = Sys.getcwd () in


(*  List.iter (fun s ->  
      Sys.chdir pwd; Sys.chdir s; 
      let project_dir = (Sys.getcwd ()) in
      ignore (Unix.system "ocp-build clean");
      Sys.chdir pwd;
      run ("mkdir -p " ^ !target);      
    ) !dirname;*)
  List.iter (fun p ->
      print_endline ("preparing opam package : "^p.package_name);
      let package_name = p.package_name ^ "_" ^
                        !version ^ ".tar.gz"
                         
      and md5sum = ref "" in
      List.iter print_endline !dirname;
      List.iteri (fun i s -> 
          print_endline "echo0";
          Sys.chdir pwd; Sys.chdir (if i > 0 then
                                      (List.hd !dirname)^"/"^s
                                    else s); 
          let project_dir = (Sys.getcwd ()) in
          ignore (Unix.system "ocp-build clean");
          
          run ("mkdir -p " ^ pwd ^"/"^ !target^"/"^p.package_name);      
          let command = "tar --exclude=_obuild --exclude=ocp-build.root* --exclude=" ^ 
                        p.package_name ^ "_"^ !version ^".tar.gz " ^ 
                        " -czf " ^ pwd ^ "/" ^ !target ^"/"^package_name ^" ."  in
          run command;
          print_endline "echo1";
          md5sum := List.hd (Str.split_delim (Str.regexp " +") (read_process ("md5sum "^pwd ^ "/" ^ !target ^"/"^package_name)));
          print_endline "echo2";
        ) !dirname;
      print_endline "echo3";
      let opam_channel = open_out (pwd ^ "/" ^ !target ^"/"^ p.package_name ^"/opam") in
      let descr_channel = open_out (pwd ^ "/" ^ !target ^"/"^ p.package_name ^"/descr") in
      let url_channel = open_out (pwd ^ "/" ^ !target ^"/"^ p.package_name ^"/url") in
      output_string opam_channel (Printf.sprintf "opam version: \"%s\" \n" !version);
      output_string opam_channel (Printf.sprintf "maintainer: \"%s\" \n" 
        (let s = ref "" in
         List.iter (fun a -> s := !s ^ (Printf.sprintf "%s " a)) p.authors; 
         !s));
      output_string opam_channel ("build: [\n"^
                     "\t[make \"build\" || "^
                     "\"ocp-build\" \"-init\" || "^
                     "\"ocp-build\" \"init\"]\n"^
                     "\t[make \"install\" || "^
                     "\"ocp-build\" \"-install\" || "^
                     "\"ocp-build\" \"install\"]\n"^
                     "]\n");
      output_string opam_channel ("remove: [\n"^
                     "\t[make \"uninstall\" || "^
                     "\"ocp-build\" \"-uninstall\" || "^
                     "\"ocp-build\" \"uninstall\"]\n"^
                     "\t[\"ocamlfind\" \"remove\" \""^
                     p.package_name^"\"]\n"^
                     "]\n");
      output_string opam_channel (Printf.sprintf"depends: [ %s ] \n" 
        (let s = ref "" in
         List.iter (fun r -> 
             s := !s ^ (Printf.sprintf "\"%s\" " (fst r)^
                        (let v = get_package_version (fst r) in
                         if v = "[distributed with Ocaml]" || v = "" then
                           "" else
                           Printf.sprintf "{>= \"%s\"} " v)
                       )
           ) p.requires; 
         !s));
      
      output_string descr_channel "Opam package generated by ocp2opam\n";
      output_string descr_channel ((String.capitalize p.package_type)^" :  "^p.package_name^"\n");
      output_string descr_channel ("by :  \n\t"^
                                   (let rec aux = function
                                      | [] -> "Someone unknown"
                                      | t::[] -> t
                                      | t::q -> t^ "\nand \t"^ aux q
                                    in aux p.authors)^"\n\n");
      List.iter (fun s -> output_string descr_channel (Printf.sprintf "%s\n" s)) !descr;

      output_string url_channel ("archive: \""^ !url ^"/"^package_name^"\"\n");
      output_string url_channel ("checksum: \""^ !md5sum ^ "\"\n");
      close_out opam_channel;
      close_out descr_channel;
      close_out url_channel;
    ) 
    (List.rev !packages);

;;
  