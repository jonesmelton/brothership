# where you are

You are in port, and leave on your next crossing once your stores are loaded.

{% for line in leg %}
- {{ line }}
{% endfor %}

The years at the worlds are the same whatever you choose. Only the hours aboard change.

# the launch

{% for line in launch %}
- {{ line }}
{% endfor %}

The port's dockhands load your stores and work the yard whoever is aboard. Every officer on the drive loads stores as fast as the dockhands do, so you leave sooner. Every officer on the hull mends in the yard until you leave, so you leave with more hull, and later. Officers at their crafts do nothing in port. {{ crew }}

# what you choose

How fast you run the coast. You burn to your speed, hold it, and brake at the far end. While you hold it, the thin gas and dust ahead strike your hull harder and more often the faster you go: coast faster and you arrive sooner, but the coast wears away more of your hull. Hands on the hull can mend it as you go, and each hand mending is a hand not at their craft. A longer crossing also gives the crew more hours at their crafts before port.

A worn hull holds your drive back: below three quarters, a half and a quarter it burns less hard, so a hull worn thin on the coast slows the approach and the next crossing's burn.

Your hull is at {{ hull }} now, and the yard mends it until you leave.

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

`ask`: what you ask your officers for while you wait in port.

- "drive": load stores, and leave sooner.
- "hull": work the yard, and leave mended.
- "nothing": you ask for nothing in particular.

`thought`: one or two sentences in your own voice: why this speed and this ask, for this crew, on this crossing.

Reply as {"cruise": "...", "ask": "...", "thought": "..."}.
