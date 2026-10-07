import json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
hits={}
TV={"breaking bad":[{"id":1396,"name":"Breaking Bad","original_name":"Breaking Bad","first_air_date":"2008-01-20","overview":"Profesor de química."}],
 "mi serie":[{"id":10,"name":"Mi Serie","original_name":"Mi Serie","first_air_date":"2018-01-01","overview":""}],
 "the office us":[{"id":2316,"name":"The Office","original_name":"The Office","first_air_date":"2005-03-24","overview":"US"},{"id":2996,"name":"The Office","original_name":"The Office","first_air_date":"2001-07-09","overview":"UK"}],
 "fargo":[{"id":60622,"name":"Fargo","original_name":"Fargo","first_air_date":"2014-04-15","overview":"a"},{"id":999,"name":"Fargo","original_name":"Fargo","first_air_date":"1996-01-01","overview":"b"}],
 "dark matter":[{"id":70,"name":"Materia Oscura","original_name":"Dark Matter","first_air_date":"2024-01-01","overview":""}],
 "dup show":[{"id":20,"name":"Dup Show","original_name":"Dup Show","first_air_date":"2020-01-01","overview":""}],
 "sneaky":[{"id":30,"name":"Sneaky","original_name":"Sneaky","first_air_date":"2020-01-01","overview":""}]}
SEASONS={1396:{1:"Pilot",2:"Cat's in the Bag...",3:"...And the Bag's in the River"},10:{1:"Uno",2:"Dos"},70:{1:"Despertar",2:"Segundo"},
 20:{1:"Piloto: Parte 1/2"},30:{1:"A",2:"B"},2316:{3:"Basketball",4:"Hot Girl"},60622:{1:"The Crocodile's Dilemma"}}
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def send(self,code,obj,hdr=None):
        b=json.dumps(obj).encode(); self.send_response(code); self.send_header("Content-Type","application/json")
        for k,v in (hdr or {}).items(): self.send_header(k,v)
        self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u=urlparse(self.path); q=parse_qs(u.query); hits[u.path]=hits.get(u.path,0)+1
        sys.stderr.write(f"{u.path} {q.get('query',[''])[0]} year={q.get('first_air_date_year')}\n"); sys.stderr.flush()
        if q.get("api_key")!=["testkey"]: return self.send(401,{})
        if u.path=="/3/search/tv":
            return self.send(200,{"results":TV.get(q["query"][0].lower(),[])})
        m=re.match(r"/3/tv/(\d+)/season/(\d+)$",u.path)
        if m:
            tv,s=int(m[1]),int(m[2])
            if tv==2316 and hits[u.path]==1: return self.send(429,{},{"Retry-After":"1"})
            eps=SEASONS.get(tv,{}) if s==1 or tv==2316 else None
            if eps is None: return self.send(404,{})
            return self.send(200,{"episodes":[{"episode_number":k,"name":v} for k,v in eps.items()]})
        self.send(404,{})
HTTPServer(("127.0.0.1",8765),H).serve_forever()
