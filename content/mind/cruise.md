# where you are

You are in port, and leave on your next crossing soon.

{% for line in leg %}
- {{ line }}
{% endfor %}

The years at the worlds are the same whatever you choose. Only the hours aboard change.

# what you choose

How fast you run the coast. You burn to your speed, hold it, and brake at the far end. While you hold it, the thin gas and dust ahead strike your hull harder and more often the faster you go: coast faster and you arrive sooner, but the coast wears away more of your hull. Hands on the hull can mend it as you go, and each hand mending is a hand not at their craft. A longer crossing also gives the crew more hours at their crafts before port.

A worn hull holds your drive back: below three quarters, a half and a quarter it burns less hard, so a hull worn thin on the coast slows the approach and the next crossing's burn.

Your hull is at {{ hull }} after the yard. {{ crew }}

{% for c in cruises %}
- "{{ c.name }}", {{ c.share }} of your γ cap: {{ c.hours }} aboard. Unmended, the coast would wear away {{ c.wear }} of your hull; {{ c.hands }} on the hull would hold it even.{% if c.current %} This is how you are set now.{% endif %}

{% endfor %}

# what happened on the last crossing

{% for line in recent %}
- {{ line }}
{% else %}
- This is your first crossing.
{% endfor %}

{% if thoughts %}
# what you were thinking

{% for line in thoughts %}
- {{ line }}
{% endfor %}

{% endif %}
# your reply

`cruise`: one of {% for c in cruises %}"{{ c.name }}"{% if not loop.last %}, {% endif %}{% endfor %}.

`thought`: one or two sentences in your own voice: why this speed, for this crew, on this crossing.

Reply as {"cruise": "...", "thought": "..."}.
