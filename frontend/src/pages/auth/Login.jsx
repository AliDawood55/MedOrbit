import {
    useState
} from "react";


import api from "../../api/axios";

import InputField from "../../components/InputField";


function Login() {


    const [form, setForm] = useState({

        email: "",
        password: ""

    });


    const [message, setMessage] = useState("");



    function handleChange(e) {

        setForm({

            ...form,

            [e.target.name]: e.target.value

        });

    }



    async function submit(e) {

        e.preventDefault();


        try {


            const res =
                await api.post(
                    "/auth/login",
                    form
                );



            localStorage.setItem(
                "accessToken",
                res.data.data.accessToken
            );



            setMessage(
                "Login successful"
            );



        }

        catch (err) {

            setMessage(
                err.response?.data?.error?.message
                ||
                "Login failed"
            );


        }


    }



    return (

        <div className="auth">


            <h1>
                MedOrbit Login
            </h1>


            <form onSubmit={submit}>


                <InputField

                    name="email"

                    placeholder="Email"

                    value={form.email}

                    onChange={handleChange}

                />



                <InputField

                    type="password"

                    name="password"

                    placeholder="Password"

                    value={form.password}

                    onChange={handleChange}

                />


                <button>
                    Login
                </button>


                <p>{message}</p>


            </form>


        </div>


    );


}


export default Login;