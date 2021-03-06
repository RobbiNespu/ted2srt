class Talk {
  constructor(params) {
    this.id = params.id;
    this.name = params.name;
    [this.speaker, this.title] = this.name.split(':').map((s) => s.trim());
    this.description = params.description;
    this.slug = params.slug;
    this.mediaSlug = params.mSlug;
    this.publishedAt = params.publishedAt;
    this.images = params.images;
    this.languages = params.languages;
    this.hasAudio = params.hasAudio;
  }
}

export class TalksProvider {
  constructor(Http) {
    this.Http = Http;
    this.talks = {};
    this.newest = [];
    this.slugToTalk = {};
  }

  add(params) {
    let id, talk;
    id = params.id;
    if (this.talks[id] && this.talks[id].languages) {
      talk = this.talks[id];
    } else {
      talk = new Talk(params);
      this.talks[id] = talk;
    }
    return talk;
  }

  fetch() {
    if (this.newest.length) {
      return Promise.resolve(this.newest);
    } else {
      return this.Http.get('/api/talks?limit=5').then((data) => {
        this.newest = data.map(this.add, this);
        return Promise.resolve(this.newest);
      }).catch(err => {
        console.log(err);
      });
    }
  }

  fetchBySlug(slug) {
    let talk = this.slugToTalk[slug];
    if (talk) {
      return Promise.resolve(talk);
    } else {
      return this.Http.get(`/api/talks/${slug}`).then((data) => {
        talk = this.add(data);
        this.slugToTalk[talk.slug] = talk;
        return Promise.resolve(talk);
      }).catch(err => {
        console.log(err);
      });
    }
  }

  search(query) {
    return this.Http.get(`/api/search?q=${query}`).then((data) => {
      let talks = data.map(this.add, this);
      return Promise.resolve(talks);
    }).catch(err => {
      console.log(err);
    });
  }

  random() {
    return this.Http.get('/api/talks/random').then((data) => {
      let talk = this.add(data);
      return Promise.resolve(talk);
    }).catch(err => {
      console.log(err);
    });
  }
}
