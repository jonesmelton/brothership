# where you are

You are in port at {{ here }}, by the star {{ star }}. You leave on your next crossing once your stores are loaded, and before then you choose where you go.

At the worlds, a crossing takes about as many years as its leg has light-years, however you fly it. Only the hours aboard change with how you fly.

# the launch

{% for line in launch %}
- {{ line }}
{% endfor %}

The port's dockhands load your stores and work the yard whoever is aboard. Every officer on the drive loads stores as fast as the dockhands do, so you leave sooner. Every officer on the hull mends in the yard until you leave, so you leave with more hull, and later. Officers at their crafts do nothing in port. {{ crew }}

A longer leg needs more stores, so you leave later for a far world. Stores already loaded count toward any leg.

# how fast you coast

You burn to your speed, hold it, and brake at the far end. While you hold it, the thin gas and dust ahead strike your hull harder and more often the faster you go: coast faster and you arrive sooner, but the coast wears away more of your hull. Hands on the hull can mend it as you go, and each hand mending is a hand not at their craft. A longer crossing also gives the crew more hours at their crafts before port.

A worn hull holds your drive back: below three quarters, a half and a quarter it burns less hard, so a hull worn thin on the coast slows the approach and the next crossing's burn.

Your hull is at {{ hull }} now, and the yard mends it until you leave.

# where you could go

A crossing is a choice, not a convenience. The nearest world is often the wrong one; when you take a short crossing, your thought says what draws you there besides the short hop.

{{ leaning }} A far world costs you stores and hull, and it gives your crew more hours aboard and more work finished at their crafts before port.

{% if short %}
You have just flown a short crossing, under eighteen light-years, and you do not fly two short crossings running. The worlds nearer than eighteen light-years are not open to you this crossing; it will be a long one.

{% endif %}
{% if came_from %}
You came here from {{ came_from }}, and you do not fly straight back.

{% endif %}
{% for c in courses %}
## {{ c.name }}, by the star {{ c.star }}

{{ c.distance }} from here. {{ c.leaves }}{% if c.current %} This is where you are bound now.{% endif %}


{{ c.visits }}{% for line in c.fleet %} {{ line }}{% endfor %}


{% for k in c.cruises %}
- "{{ k.name }}", {{ k.share }} of your γ cap: {{ k.hours }} aboard. Unmended, the coast would wear away {{ k.wear }} of your hull; {{ k.hands }} on the hull would hold it even.{% if k.current %} This is how you are set now.{% endif %}

{% endfor %}

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

`course`: one of {% for c in courses %}"{{ c.name }}"{% if not loop.last %}, {% endif %}{% endfor %}. You tell the crew where you are going once you have chosen.

`cruise`: one of {% for k in courses[0].cruises %}"{{ k.name }}"{% if not loop.last %}, {% endif %}{% endfor %}.

`ask`: what you ask your officers for while you wait in port.

- "drive": load stores, and leave sooner.
- "hull": work the yard, and leave mended.
- "nothing": you ask for nothing in particular.

`thought`: one or two sentences in your own voice: why this world, this speed and this ask, for this crew.

Reply as {"course": "...", "cruise": "...", "ask": "...", "thought": "..."}.
