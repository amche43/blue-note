import com.sun.net.httpserver.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** Personal v1 sync companion. No paid service or third-party Java dependency.
 * HTTPS termination is required before exposing this service outside a private LAN.
 * One instance/token owns one personal journal; this is not a public multi-user API.
 */
public final class BlueNoteServer {
  static final int LIMIT = 8 * 1024 * 1024;
  final Path file;
  final byte[] auth;
  Map<String, Map<String,Object>> events = new LinkedHashMap<>();

  BlueNoteServer(Path file, String token) throws IOException {
    if (token == null || token.length() < 32) throw new IllegalArgumentException("BLUE_NOTE_TOKEN must contain at least 32 characters");
    this.file = file.toAbsolutePath();
    auth = ("Bearer " + token).getBytes(StandardCharsets.UTF_8);
    if (Files.exists(file)) events = validate(Json.parse(Files.readString(file)));
  }

  @SuppressWarnings("unchecked")
  static Map<String, Map<String,Object>> validate(Object value) {
    if (!(value instanceof Map<?,?> root) || !List.of(1L, 2L).contains(root.get("schemaVersion")) || !(root.get("events") instanceof List<?> list) || list.size() > 20000)
      throw new IllegalArgumentException("Invalid journal");
    Map<String,Map<String,Object>> result = new LinkedHashMap<>();
    for (Object item : list) {
      if (!(item instanceof Map<?,?> raw)) throw new IllegalArgumentException("Invalid event");
      Map<String,Object> e = (Map<String,Object>)raw;
      if (!(e.get("id") instanceof String id) || !id.matches("[a-f0-9]{32}") ||
          !(e.get("lessonId") instanceof String lesson) || !lesson.matches("[a-z0-9-]{1,80}") ||
          !(e.get("at") instanceof Long at) || at < 0 || at > System.currentTimeMillis()+86400000L ||
          !(e.get("payload") instanceof Map<?,?> payload)) throw new IllegalArgumentException("Invalid event fields");
      if ("note".equals(e.get("type"))) {
        if (!(payload.get("text") instanceof String text) || text.length() > 20000) throw new IllegalArgumentException("Invalid note");
      } else if ("attempt".equals(e.get("type"))) {
        if (!List.of("again","hard","good").contains(payload.get("rating")) ||
            !(payload.get("assisted") instanceof Boolean) || !(payload.get("correct") instanceof Boolean) ||
            !(payload.get("variantId") instanceof String) || !(payload.get("reason") instanceof String))
          throw new IllegalArgumentException("Invalid attempt");
      } else if ("question".equals(e.get("type"))) {
        if (!Long.valueOf(2).equals(root.get("schemaVersion")) || !lesson.matches("user-[a-f0-9]{32}") || !(payload.get("deleted") instanceof Boolean))
          throw new IllegalArgumentException("Invalid question revision");
        var limits = Map.ofEntries(Map.entry("title",120), Map.entry("subject",60), Map.entry("chapter",120),
          Map.entry("prompt",18000), Map.entry("formula",4000), Map.entry("answer",18000), Map.entry("trigger",4000),
          Map.entry("action",4000), Map.entry("conditions",4000), Map.entry("pitfall",4000), Map.entry("source",1000), Map.entry("origin",80));
        for (var field : limits.entrySet()) {
          if (!(payload.get(field.getKey()) instanceof String text) || text.length() > field.getValue())
            throw new IllegalArgumentException("Invalid question field");
        }
        for (String required : List.of("title", "subject"))
          if (((String)payload.get(required)).isBlank()) throw new IllegalArgumentException("Empty question field");
        boolean photo = false, canvas = false;
        for (String name : List.of("questionPhoto","answerPhoto")) {
          Object valuePhoto = payload.containsKey(name) ? payload.get(name) : "";
          if (!(valuePhoto instanceof String encoded) || encoded.length() > 4*1024*1024)
            throw new IllegalArgumentException("Invalid photo");
          if (!encoded.isEmpty()) {
            byte[] image=Base64.getDecoder().decode(encoded);
            if (image.length<8 || !((image[0]&255)==137 && image[1]==80 && image[2]==78 && image[3]==71) &&
                !((image[0]&255)==255 && (image[1]&255)==216)) throw new IllegalArgumentException("Invalid photo signature");
            if (name.equals("questionPhoto")) photo=true;
          }
        }
        if (payload.containsKey("canvas")) {
          if (!(payload.get("canvas") instanceof String ink) || ink.length()>8*1024*1024)
            throw new IllegalArgumentException("Invalid canvas size");
          if (!ink.isEmpty()) {
            if (!(Json.parse(ink) instanceof Map<?,?> doc) || !Long.valueOf(1).equals(doc.get("version")) ||
                !(doc.get("elements") instanceof List<?> actions) || actions.size()>3000 || !(doc.get("ruled") instanceof Boolean))
              throw new IllegalArgumentException("Invalid canvas document");
            canvas=true;
          }
        }
        if (((String)payload.get("prompt")).isBlank() && !photo && !canvas)
          throw new IllegalArgumentException("Empty question content");
        for (var field : Map.of("notebookId",40,"notebookTitle",80,"questionNumber",10).entrySet())
          if (payload.containsKey(field.getKey()) && (!(payload.get(field.getKey()) instanceof String text) || text.length()>field.getValue()))
            throw new IllegalArgumentException("Invalid notebook field");
        String book = payload.get("notebookId") instanceof String bookValue ? bookValue : "";
        for (String field : List.of("firstThought","errorReason","summary"))
          if (payload.containsKey(field) && (!(payload.get(field) instanceof String thought) || thought.length()>4000))
            throw new IllegalArgumentException("Invalid personal thought");
        if (payload.containsKey("contentKind") && !List.of("question","knowledge").contains(payload.get("contentKind")))
          throw new IllegalArgumentException("Invalid content kind");
        String title = payload.get("notebookTitle") instanceof String titleValue ? titleValue : "";
        String number = payload.get("questionNumber") instanceof String numberValue ? numberValue : "";
        if ((!book.isEmpty() && (!book.matches("book-[a-f0-9]{32}") || title.isBlank() || !number.matches("[1-9][0-9]{0,8}"))) ||
            (book.isEmpty() && (!title.isEmpty() || !number.isEmpty()))) throw new IllegalArgumentException("Invalid notebook reference");
      } else throw new IllegalArgumentException("Invalid event type");
      var previous = result.putIfAbsent(id,e);
      if (previous != null && !previous.equals(e)) throw new IllegalArgumentException("Conflicting event ID");
    }
    return result;
  }

  synchronized String merge(Object input) throws IOException {
    final var incoming = validate(input);
    final var merged = new LinkedHashMap<>(events);
    for (var item : incoming.entrySet()) {
      var previous = merged.putIfAbsent(item.getKey(),item.getValue());
      if (previous != null && !previous.equals(item.getValue())) throw new IllegalArgumentException("Conflicting event ID");
    }
    if (merged.size() > 20000) throw new IllegalArgumentException("Journal capacity reached");
    final int schema = merged.values().stream().anyMatch(event -> "question".equals(event.get("type"))) ? 2 : 1;
    final String encoded = Json.write(Map.of("schemaVersion",schema,"events",new ArrayList<>(merged.values())));
    final byte[] bytes = encoded.getBytes(StandardCharsets.UTF_8);
    if (bytes.length > LIMIT) throw new IllegalArgumentException("Journal capacity reached");
    Files.createDirectories(file.getParent());
    final Path temporary = file.resolveSibling(file.getFileName()+".tmp");
    try (FileChannel channel = FileChannel.open(temporary,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING,StandardOpenOption.WRITE)) {
      var buffer = java.nio.ByteBuffer.wrap(bytes);
      while(buffer.hasRemaining()) channel.write(buffer);
      channel.force(true);
    }
    // Fail without acknowledging or altering in-memory state if atomic replace
    // isn't supported on the selected filesystem.
    Files.move(temporary,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
    events = merged;
    return encoded;
  }

  void handle(HttpExchange exchange) throws IOException {
    try {
      if (!exchange.getRequestURI().getPath().equals("/v1/sync")) {reply(exchange,404,"{\"error\":\"not_found\"}");return;}
      if (!exchange.getRequestMethod().equals("POST")) {reply(exchange,405,"{\"error\":\"method_not_allowed\"}");return;}
      final String supplied = exchange.getRequestHeaders().getFirst("Authorization");
      if (supplied == null || !MessageDigest.isEqual(auth,supplied.getBytes(StandardCharsets.UTF_8))) {
        reply(exchange,401,"{\"error\":\"unauthorized\"}");return;
      }
      byte[] body = exchange.getRequestBody().readNBytes(LIMIT+1);
      if (body.length > LIMIT) {reply(exchange,413,"{\"error\":\"too_large\"}");return;}
      reply(exchange,200,merge(Json.parse(new String(body,StandardCharsets.UTF_8))));
    } catch (IllegalArgumentException error) {reply(exchange,400,"{\"error\":\"invalid_or_conflicting_journal\"}");}
    catch (IOException error) {reply(exchange,500,"{\"error\":\"storage_error\"}");}
    finally {exchange.close();}
  }
  static void reply(HttpExchange e,int code,String text) throws IOException {
    final byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
    e.getResponseHeaders().set("Content-Type","application/json; charset=utf-8");
    e.getResponseHeaders().set("Cache-Control","no-store");
    e.sendResponseHeaders(code,bytes.length);
    e.getResponseBody().write(bytes);
  }
  public static void main(String[] args) throws Exception {
    String bind = System.getenv().getOrDefault("BLUE_NOTE_BIND","127.0.0.1");
    int port = Integer.parseInt(System.getenv().getOrDefault("BLUE_NOTE_PORT","8787"));
    Path file = Path.of(System.getenv().getOrDefault("BLUE_NOTE_DATA","data/journal.json"));
    BlueNoteServer app = new BlueNoteServer(file,System.getenv("BLUE_NOTE_TOKEN"));
    HttpServer server = HttpServer.create(new InetSocketAddress(bind,port),32);
    server.createContext("/v1/sync",app::handle);
    server.setExecutor(new ThreadPoolExecutor(2,4,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(32),new ThreadPoolExecutor.CallerRunsPolicy()));
    Runtime.getRuntime().addShutdownHook(new Thread(() -> server.stop(1)));
    server.start();
    System.out.println("Blue Note personal sync listening on "+bind+":"+port+"; journal loaded: "+app.events.size());
  }

  /** Small strict JSON codec: bounded depth, duplicate-key rejection, no reflection. */
  static final class Json {
    final String input; int position;
    Json(String input) {this.input=input;}
    static Object parse(String text) {
      Json parser = new Json(text); Object result=parser.value(0); parser.space();
      if(parser.position!=text.length()) throw new IllegalArgumentException("Trailing data");
      return result;
    }
    void space(){while(position<input.length() && " \t\r\n".indexOf(input.charAt(position))>=0)position++;}
    char next(){if(position>=input.length())throw new IllegalArgumentException("Unexpected end");return input.charAt(position++);}
    void require(char c){space();if(next()!=c)throw new IllegalArgumentException("Unexpected token");}
    Object value(int depth) {
      if(depth>32)throw new IllegalArgumentException("Too deep");space();
      if(position>=input.length())throw new IllegalArgumentException("Missing value");
      char c=input.charAt(position);
      if(c=='"')return string();
      if(c=='{'){
        position++;Map<String,Object> object=new LinkedHashMap<>();space();
        if(position<input.length()&&input.charAt(position)=='}'){position++;return object;}
        while(true){space();String key=string();require(':');
          if(object.containsKey(key))throw new IllegalArgumentException("Duplicate key");
          object.put(key,value(depth+1));space();char close=next();if(close=='}')return object;if(close!=',')throw new IllegalArgumentException("Missing comma");}
      }
      if(c=='['){
        position++;List<Object> list=new ArrayList<>();space();
        if(position<input.length()&&input.charAt(position)==']'){position++;return list;}
        while(true){list.add(value(depth+1));space();char close=next();if(close==']')return list;if(close!=',')throw new IllegalArgumentException("Missing comma");}
      }
      for(String literal:List.of("true","false","null"))if(input.startsWith(literal,position)){
        position+=literal.length();return literal.equals("null")?null:literal.equals("true");}
      int start=position;
      if(c=='-')position++;
      while(position<input.length()&&Character.isDigit(input.charAt(position)))position++;
      if(position<input.length()&&input.charAt(position)=='.') {position++;while(position<input.length()&&Character.isDigit(input.charAt(position)))position++;}
      if(position<input.length()&&(input.charAt(position)=='e'||input.charAt(position)=='E')) {
        position++;if(position<input.length()&&(input.charAt(position)=='+'||input.charAt(position)=='-'))position++;
        while(position<input.length()&&Character.isDigit(input.charAt(position)))position++;
      }
      String number=input.substring(start,position);
      if(!number.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"))throw new IllegalArgumentException("Invalid number");
      try{
        if(number.indexOf('.')<0&&number.indexOf('e')<0&&number.indexOf('E')<0)return Long.parseLong(number);
        double parsed=Double.parseDouble(number);if(!Double.isFinite(parsed))throw new IllegalArgumentException("Non-finite number");return parsed;
      }catch(NumberFormatException e){throw new IllegalArgumentException("Invalid number");}
    }
    String string(){
      require('"');StringBuilder out=new StringBuilder();
      while(true){char c=next();if(c=='"')return out.toString();
        if(c<32)throw new IllegalArgumentException("Control character");
        if(c=='\\'){
          char escaped=next();
          switch(escaped){
            case '"','\\','/' -> out.append(escaped);
            case 'b' -> out.append('\b');case 'f' -> out.append('\f');case 'n' -> out.append('\n');case 'r' -> out.append('\r');case 't' -> out.append('\t');
            case 'u' -> {if(position+4>input.length())throw new IllegalArgumentException("Bad unicode");
              try{out.append((char)Integer.parseInt(input.substring(position,position+4),16));}catch(NumberFormatException e){throw new IllegalArgumentException("Bad unicode");}position+=4;}
            default -> throw new IllegalArgumentException("Bad escape");
          }
        }else out.append(c);
      }
    }
    static String write(Object object){
      if(object==null)return "null";
      if(object instanceof String s){StringBuilder out=new StringBuilder("\"");for(char c:s.toCharArray()){
        switch(c){case '"' -> out.append("\\\"");case '\\' -> out.append("\\\\");case '\n' -> out.append("\\n");case '\r' -> out.append("\\r");case '\t' -> out.append("\\t");
          default -> {if(c<32)out.append(String.format("\\u%04x",(int)c));else out.append(c);}}
        }return out.append('"').toString();}
      if(object instanceof Number||object instanceof Boolean)return object.toString();
      if(object instanceof List<?> list){StringJoiner join=new StringJoiner(",","[","]");for(Object item:list)join.add(write(item));return join.toString();}
      if(object instanceof Map<?,?> map){StringJoiner join=new StringJoiner(",","{","}");for(var entry:map.entrySet())join.add(write(entry.getKey())+":"+write(entry.getValue()));return join.toString();}
      throw new IllegalArgumentException("Unsupported JSON type");
    }
  }
}
