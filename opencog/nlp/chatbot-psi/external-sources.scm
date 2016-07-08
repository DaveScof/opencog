(use-modules (ice-9 threads))
(use-modules (opencog) (opencog exec)(opencog python))

;-------------------------------------------------------------------------------
(python-eval "
from opencog.atomspace import AtomSpace, types, TruthValue

import urllib2
import json
import threading
import xml.etree.ElementTree as ET

atomspace = ''

def set_atomspace(atsp):
    global atomspace
    atomspace = atsp
    return TruthValue(1, 1)

# TODO: Attribution!
def to_duckduckgo(qq):
    global atomspace

    # Anchor for the result
    answer_anchor = atomspace.add_node(types.AnchorNode, 'Chatbot: DuckDuckGoAnswers')

    # Avoid HTTP Error 400: Bad Request
    query = qq.name.replace(' ', '+')

    # Send the query
    response = urllib2.urlopen('http://api.duckduckgo.com/?q=' + query + '&format=json').read()
    result = json.loads(response)
    abstract_text = result['AbstractText']

    if abstract_text:
        word_nodes = []
        words = abstract_text.split(' ')
        for word in words:
            word_nodes.append(atomspace.add_node(types.WordNode, word))
        ans = atomspace.add_link(types.ListLink, word_nodes)
        atomspace.add_link(types.StateLink, [answer_anchor, ans])
    else:
        no_result = atomspace.add_node(types.ConceptNode, 'Chatbot: NoResult')
        atomspace.add_link(types.StateLink, [answer_anchor, no_result])

def to_wolframalpha(qq, aid):
    global atomspace
    appid = aid.name

    # Check if we have an AppID
    if appid == '':
        raise ValueError('AppID for Wolfram|Alpha Webservice API is missing!')

    # Anchor for the result
    answer_anchor = atomspace.add_node(types.AnchorNode, 'Chatbot: WolframAlphaAnswers')

    # Avoid HTTP Error 400: Bad Request
    query = qq.name.replace(' ', '+')

    url_1 = 'http://api.wolframalpha.com/v2/query?appid='
    url_2 = '&input='
    url_3 = '&format=plaintext'
    full_url = url_1 + appid + url_2 + query + url_3

    response = ET.fromstring(urllib2.urlopen(full_url).read())
    result = ''

    # List of pod titles it's currently checking:
    # - Result
    # - Definition
    # - Basic definition
    # Usually the answer is in 'Result', if not, usually one of
    # them has the answer
    # TODO: Expand to cover more if needed
    for pod in response.iter('pod'):
        title = pod.get('title')
        if title == 'Result' or title == 'Definition' or title == 'Basic definition':
            result = pod.find('subpod').find('plaintext').text

    # Post-process the result a bit
    if result:
        # Sometimes '|' exists in the result
        # Also skip brackets
        result = result.replace('|', '').replace('(', '').replace(')', '')

        # For common punctuations, to turn them into actual WordNode later
        result = result.replace(',', ' ,').replace('.', ' .').replace('?', ' ?').replace('!', ' !')

    # Write to AtomSpace
    if result:
        word_nodes = []
        words = result.split(' ')
        for word in words:
            if word:
                word_nodes.append(atomspace.add_node(types.WordNode, word))
        ans = atomspace.add_link(types.ListLink, word_nodes)
        atomspace.add_link(types.StateLink, [answer_anchor, ans])
    else:
        no_result = atomspace.add_node(types.ConceptNode, 'Chatbot: NoResult')
        atomspace.add_link(types.StateLink, [answer_anchor, no_result])

def call_duckduckgo(qq):
    t = threading.Thread(target=to_duckduckgo, args=(qq,))
    t.start()
    return TruthValue(1, 1)

def call_wolframalpha(qq, aid):
    t = threading.Thread(target=to_wolframalpha, args=(qq, aid))
    t.start()
    return TruthValue(1, 1)
")

; Get the current atomspace from guile
(python-call-with-as "set_atomspace" (cog-atomspace))

; AppID for Wolfram|Alpha Webservice API
(define appid "")

(define (set-appid id)
    (set! appid id)
)

(define-public (ask-duckduckgo)
    (State duckduckgo-search search-started)

    ; TODO: We may want to actually nlp-parse the answer, but a typical answer
    ; of this type seems to be very long (a paragraph), split into sentences
    ; and then parse?
    (begin-thread
        (cog-evaluate! (Evaluation (GroundedPredicate "py: call_duckduckgo")
            (List (get-input-text-node))))
        (State duckduckgo-search search-finished)
    )
)

(define-public (ask-wolframalpha)
    (if (not (equal? appid ""))
        (begin-thread
            (define appid_node (Node appid))
            (State wolframalpha-search search-started)

            (cog-evaluate! (Evaluation (GroundedPredicate "py: call_wolframalpha")
                (List (get-input-text-node) appid_node)))
            (State wolframalpha-search search-finished)
            (cog-extract appid_node)
        )
    )
)
