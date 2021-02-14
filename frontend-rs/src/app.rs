
use serde::Deserialize;
use url::*;
use wasm_bindgen::prelude::*;
use yew::events::*;
use yew::services::fetch::{FetchService, FetchTask, Request, Response};
use yew::{
    format::{Json, Nothing},
    prelude::*,
};
use yew_router::*;

#[derive(Switch)]
enum AppRoute {
    #[to = "/cards"]
    Cards,
    #[to = "/screen"]
    Screen,
    #[to = "/timeline"]
    Timeline,
    #[to = "/addnote"]
    AddNote,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Entry {
    time: String,
    #[serde(rename(deserialize = "entryID"))]
    entry_id: i32,
    content: String,
    date: String,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Cache {
    #[serde(rename(deserialize = "cvTime"))]
    time: String,
    #[serde(rename(deserialize = "cvForeignID"))]
    entry_id: i32,
    #[serde(rename(deserialize = "cvContent"))]
    content: Option<String>,
    #[serde(rename(deserialize = "cvDate"))]
    date: String,
    #[serde(rename(deserialize = "cvUrl"))]
    url: Option<String>,
    #[serde(rename(deserialize = "cvScreenshotFile"))]
    screenshot_file: Option<String>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Tag {
    tag_name: String,
}

#[derive(Debug)]
pub enum Msg {
    GetEntries,
    ReceiveEntries(Result<Vec<Cache>, anyhow::Error>),
    ReceiveTags(Result<Vec<String>, anyhow::Error>),
    KeyDown,
    CardMouseOver(MouseEvent),
    TagMouseOver(MouseEvent, String),
    SortByDate,
    SortByUrl,
}

#[derive(Debug)]
pub struct App {
    cache_task: Option<FetchTask>,
    tag_task: Option<FetchTask>,
    entries: Option<Vec<Cache>>,
    tags: Option<Vec<String>>,
    link: ComponentLink<Self>,
    error: Option<String>,
    query: String,
}

impl App {
    fn view_entries(&self) -> Html {
        match self.entries {
            Some(ref entries) => {
                log::info!("{:#?} results fetched.", entries.len());
                html! {
                    {
                        for entries.iter().map(|mut item| {
                            // TODO - handle None for options
                            let parsed = Url::parse(item.url.as_ref().unwrap_or(&"".to_owned()));
                            html! {
                                <div class="card" onmouseover=self.link.callback(|m| { Msg::CardMouseOver(m) })>
                                    <h4>
                                        { item.date.clone() }
                                    </h4>
                                    <hr/>
                                    <img src=item.screenshot_file.clone().unwrap_or("".to_owned())/>
                                    {
                                        match &parsed {
                                            Ok(x) => { x.host_str().unwrap() }
                                            Err(error) => { "" }
                                        }
                                    }
                                    <a href={ item.url.as_ref().unwrap_or(&"".to_owned()).clone() }>
                                        { item.content.clone().unwrap_or("".to_owned()) }
                                    </a>
                                </div>
                            }
                        })
                    }
                }
            }
            None => {
                html! { <div> {"No Content"} </div> }
            }
        }
    }

    fn view_navbar(&self) -> Html {
        html! {
            <nav class="navbar navbar-expand-lg navbar-light bg-light">
                <a class="navbar-brand" href="#"> { "note2self" } </a>
                <div class="collapse navbar-collapse" id="navbarNav">
                    <ul class="navbar-nav">
                        <li class="nav-item active">
                            <a class="nav-link" href="#">{ "Cards"} </a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="#">{ "Screens" }</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="#">{ "Timeline" }</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="#">{ "Add Note" }</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" href="#">{ "System" }</a>
                        </li>
                    </ul>
                </div>
            </nav>
        }
    }

    fn view_topic_tag(&self, item: &str) -> Html {
        html! {
        <div class="topic-tag">
         { item.clone() }
        </div>
        }
        /*
        html! {
        <div class="topic-tag" onmouseover=self.clone().link.clone().callback(|m| Msg::TagMouseOver(m, item.to_string().clone()) )>
        // <div class="topic-tag" onmouseover=self.link.callback(|m| Msg::TagMouseOver(m, item.to_string().clone()) )>
         { item.clone() }
        </div>
        }
        */
    }
}

impl Component for App {
    type Message = Msg;
    type Properties = ();

    fn create(_props: Self::Properties, link: ComponentLink<Self>) -> Self {
        log::info!("Creating component");
        let cb = link.callback_once(|_: String| Msg::GetEntries);
        cb.emit("".to_string()); // TODO - what's the right way to handle a message without parameters
        log::info!("sent message");

        // let kb_cb = link.callback(Msg::KeyDown);
        Self {
            cache_task: None,
            tag_task: None,
            entries: None, //Some(Vec::<Entry>::new()),
            tags: None,
            link,
            error: None,
            query: "http://localhost:3000/all/cache".to_string(),
        }
    }

    fn change(&mut self, _props: Self::Properties) -> bool {
        false
    }

    fn update(&mut self, msg: Self::Message) -> bool {
        use Msg::*;
        log::info!("update");

        match msg {
            GetEntries => {
                // define request
                log::info!("submitting cache request");
                let request = Request::get(&self.query)
                    .body(Nothing)
                    .expect("Could not build request.");
                // define callback
                let callback = self.link.callback_once(
                    |response: Response<Json<Result<Vec<Cache>, anyhow::Error>>>| {
                        let Json(data) = response.into_body();
                        Msg::ReceiveEntries(data)
                    },
                );
                // task
                let task = FetchService::fetch(request, callback).expect("failed to start request");
                self.cache_task = Some(task);

                // define request
                log::info!("submitting tag request");
                let request = Request::get("http://localhost:3000/all/tags")
                    .body(Nothing)
                    .expect("Could not build request.");
                // define callback
                let callback = self.link.callback_once(
                    |response: Response<Json<Result<Vec<String>, anyhow::Error>>>| {
                        let Json(data) = response.into_body();
                        Msg::ReceiveTags(data)
                    },
                );
                // task
                let task = FetchService::fetch(request, callback).expect("failed to start request");
                self.tag_task = Some(task);

                false // redraw page
            }
            Msg::ReceiveEntries(response) => {
                match response {
                    Ok(result) => {
                        // log::info!("Update: {:#?}", result);
                        self.entries = Some(result);
                    }
                    Err(error) => {
                        log::info!("cache receive error, error is:");
                        log::info!("{}", &error.to_string());
                        self.error = Some(error.to_string());
                    }
                }
                self.cache_task = None;
                true
            }
            ReceiveTags(response) => {
                match response {
                    Ok(result) => {
                        self.tags = Some(result);
                    }
                    Err(error) => {
                        log::info!("tag receive error, error is:");
                        log::info!("{}", &error.to_string());
                        self.error = Some(error.to_string());
                    }
                }
                self.tag_task = None;
                true
            }
            KeyDown => {
                log::info!("keydown event");
                false
            }
            CardMouseOver(_m) => {
                log::info!("card mouseover event");
                true
            }
            TagMouseOver(m, tag_name) => {
                log::info!("tag mouseover event");
                log::info!("{:?}", tag_name);
                log::info!("{:?}", m.to_string());
                true
            }

            SortByDate => {
                log::info!("sort date");
                self.query = "http://localhost:3000/all/cache?sort=time".to_string();
                // self.link.send_self(GetEntries);
                self.link.send_message(GetEntries);
                true
            }
            SortByUrl => {
                log::info!("sort url");
                self.query = "http://localhost:3000/all/cache?sort=url".to_string();
                self.link.send_message(GetEntries);
                true
            }
        }
    }

    fn view(&self) -> Html {


        let render_tags = |exist_tags: &Vec<String>| {
            html! {
            <div>
              {
                for exist_tags.iter().map(|item| { self.view_topic_tag(item) } )
              }
            </div>
            }
        };
        html! {
          <div class="main-outer" onkeydown={ self.link.callback(move |e: KeyboardEvent|
              { e.stop_propagation(); Msg::KeyDown })}>
              { self.view_navbar() }

              <div class="main-inner">

                  <h1>
                      { "note2self" }
                  </h1>
                  <hr/>
                  <p/>
                  <input type="text" class="search-input" placeholder="Search" />
                  <button class="sort-button" onclick=self.link.callback(|m| { Msg::SortByDate })>{"Sort by Date"}</button>
                  <button class="sort-button" onclick=self.link.callback(|m| { Msg::SortByUrl })>{"Sort by Url"}</button>

                  <p/>
                  <div class="twocol">
                      <div class="cards">
                          { self.view_entries() }
                      </div>
                      <div>
                          {

                            match &self.tags {
                                Some(exist_tags) => {
                                      // log::info!("{:#?} results fetched.", exist_tags.len());
                                      // let link = self.link.clone();
                                      render_tags(&exist_tags)
                                      /*
                                      html! {
                                      <div>
                                          {
                                              for exist_tags.iter().map(|item| { self.view_topic_tag(item) } )
                                              // self.view_topic_tag(&"hello".to_string())
                                          }
                                      </div>
                                      }
                                      */
                              }
                              None => html! { { "No tags" } } }
                          }
                      </div>
                  </div>
              </div>
          </div>
        }
    }
}